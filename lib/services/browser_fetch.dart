import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';

/// 用 App 內的 WebView 當論壇的傳輸層。
///
/// **為什麼需要**：論壇擋在 Cloudflare 後面時，光把解出來的 `cf_clearance`
/// 搬給 HTTP 客戶端**不夠**——實測還是 403。票是真的，但 Cloudflare 也看
/// TLS 指紋，拿票的必須真的是瀏覽器。
///
/// 所以連請求本身都交給 WebView：在論壇自己的頁面裡跑 `fetch()`，同源、
/// 自動帶齊所有 cookie（含 HttpOnly 的 `cf_clearance`），CF 看到的就是
/// 不折不扣的瀏覽器。回來的 HTML 再餵給原本那套解析器。
///
/// 只在 Cloudflare 擋著時才啟用——它比直連慢得多。
class BrowserFetch {
  BrowserFetch._();
  static final BrowserFetch instance = BrowserFetch._();

  static const _channel = 'GMBridge';

  /// 給宿主 widget 用：控制器建好之後才能把 WebView 掛上畫面
  final ready = ValueNotifier<WebViewController?>(null);

  /// 驗證頁正在顯示這顆 WebView。
  ///
  /// **全 App 只有一顆 WebView**：發請求的和給使用者解驗證的是同一個。
  /// 兩顆的話，使用者在看得見的那顆解完，隱形的那顆還停在挑戰頁上——
  /// 而它是透明的，連「我是人類」都點不到，於是永遠解不開。
  ///
  /// 一個 controller 同時只能掛在一個 WebViewWidget 上，所以驗證頁顯示時
  /// 常駐的宿主要讓位。
  final presenting = ValueNotifier<bool>(false);

  WebViewController? get controller => ready.value;

  /// 圖片子網域專用的 WebView。
  ///
  /// **為什麼需要**：版塊圖示、勳章、帖子裡的圖都放在 `img.gamemale.com`，
  /// 跟論壇本體不同來源。從停在 `www` 的頁面 `fetch()` 過去是跨來源請求，
  /// 而那個網域不送 CORS 標頭，直接被瀏覽器擋掉——實機症狀是「頭像有、
  /// 其他圖全滅」（頭像在 www 底下，同源所以會動）。
  ///
  /// 那個子網域同樣被 Cloudflare 擋著，所以也不能改用一般的 HTTP 客戶端。
  /// 只能再開一顆停在該來源的 WebView，讓請求變成同源。
  /// 這顆不給使用者看——圖片是靜態資源，Cloudflare 通常會自己放行。
  final _byOrigin = <String, WebViewController>{};

  /// 開了幾個額外來源。宿主靠它知道要重建、把新的 WebView 掛上畫面。
  final origins = ValueNotifier<int>(0);

  /// 挑一顆跟目標網址**同來源**的 WebView，沒有就開一顆。
  Future<WebViewController> _viewFor(String url) async {
    final origin = Uri.tryParse(url)?.origin ?? kForumOrigin;
    final main = ready.value;
    if (main == null) throw const DiscuzException('瀏覽器傳輸沒有就緒');
    if (origin == kForumOrigin) return main;

    final existing = _byOrigin[origin];
    if (existing != null) return existing;

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(Api.userAgent)
      ..addJavaScriptChannel(_channel, onMessageReceived: _onMessage);
    _byOrigin[origin] = c;
    origins.value++; // 掛上畫面，JS 才跑得動

    // 載入該來源的任一頁面，把文件的 origin 定在那裡，之後 fetch 才同源。
    // 被 Cloudflare 擋的話這裡拿到的是挑戰頁，真瀏覽器通常會自己解掉。
    await c.loadRequest(Uri.parse('$origin/'));
    await Future<void>.delayed(const Duration(seconds: 3));
    return c;
  }

  Completer<void>? _settled;

  /// 驗證頁會暫時接管導覽處理（它要自己等「頁面變成論壇」那一刻），
  /// 離開時把平常那份裝回去。
  void restoreDelegate() {
    final c = ready.value;
    if (c == null) return;
    c.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          final settled = _settled;
          if (settled == null || settled.isCompleted) return;
          if (await _isForum(c)) settled.complete();
        },
        onWebResourceError: (_) {
          final settled = _settled;
          if (settled != null && !settled.isCompleted) settled.complete();
        },
      ),
    );
  }

  Future<void>? _booting;
  final _pending = <int, Completer<String>>{};
  int _seq = 0;

  /// 先把 WebView 暖起來，不等它完成。
  ///
  /// 上次啟動就在走瀏覽器的話，App 一開就呼叫這支——不然使用者會對著
  /// 轉圈圈等它從零開始載入論壇（實機上就是這個症狀）。
  void warmUp() {
    _ensureReady().catchError((_) {});
  }

  Future<void> _ensureReady() {
    if (ready.value != null) return Future.value();
    return _booting ??= _boot();
  }

  Future<void> _boot() async {
    // 先把 App 的 cookie 灌進去，WebView 開起來就是已登入狀態
    final jar = WebViewCookieManager();
    for (final cookie in await Api.instance.allCookies()) {
      await jar.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: Uri.parse(kForumOrigin).host,
        ),
      );
    }

    final settled = Completer<void>();
    // 分兩步：導覽處理常式裡要用到 c 本身（探測頁面內容），
    // 寫成串接的話會在宣告完成前就參照到它
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // UA 要跟 Api 一致：cookie 與 Cloudflare 的判斷都跟 UA 綁在一起
      ..setUserAgent(Api.userAgent)
      ..addJavaScriptChannel(_channel, onMessageReceived: _onMessage);

    _settled = settled;
    c.setNavigationDelegate(
      NavigationDelegate(
        // ⚠️ 不能在第一個 onPageFinished 就當作就緒。
        // Cloudflare 的挑戰頁自己也會觸發這個事件，那時候頁面上是挑戰
        // 不是論壇——直接去 fetch 只會拿回挑戰頁的 HTML。
        // 要等到頁面**真的是論壇**（挑戰解掉後 CF 會自己重新導向）。
        onPageFinished: (_) async {
          if (settled.isCompleted) return;
          if (await _isForum(c)) {
            settled.complete();
          }
        },
        onWebResourceError: (_) {
          if (!settled.isCompleted) settled.complete();
        },
      ),
    );

    // 先掛上畫面再載入。順序反過來的話，第一次 onPageFinished 觸發時
    // WebView 還沒進 widget 樹，iOS 上那支探測用的 JS 會直接失敗。
    ready.value = c;
    await c.loadRequest(Uri.parse('$kForumOrigin/forum.php?mobile=2'));

    // **刻意不在這裡等頁面載完。**
    //
    // 等的話第一個請求就要跟著卡住十幾秒，使用者對著空白轉圈圈——實機
    // 回報的就是這個。是不是挑戰交給 _ensureOnForum 判斷，一發現就馬上
    // 把驗證頁叫出來。
    //
    // 提早叫出來是零成本的：驗證頁顯示的就是這同一顆 WebView，如果其實
    // 只是還在載入，載完的瞬間它會偵測到論壇並自己關閉。
  }

  /// 發請求前先確定頁面**真的停在論壇上**。
  ///
  /// 少了這步會出現兩種症狀：停在挑戰頁時 fetch 拿回的是挑戰 HTML；
  /// 而挑戰頁解題過程中會自己重新導向，把進行中的 fetch 一起取消掉——
  /// Safari 回報的是「TypeError: Load failed」，看起來像網路斷了，
  /// 其實只是我們在錯的時機發了請求。
  /// 上次確認過「頁面是論壇」的時間。
  ///
  /// 首頁一次會有二十幾張圖同時要抓，每張都各自探測一次的話，等於對同一顆
  /// WebView 併發丟出幾十次 JS 求值。只要其中一次在高負載下回傳不如預期，
  /// 那張圖就被判成還在挑戰頁而失敗——實機症狀是文字讀得到、圖片全滅。
  /// 短時間內共用同一個結論就好。
  DateTime? _forumOkAt;
  static const _probeCache = Duration(seconds: 8);

  Future<void> _ensureOnForum(WebViewController c) async {
    final ok = _forumOkAt;
    if (ok != null && DateTime.now().difference(ok) < _probeCache) return;

    if (await _isForum(c)) {
      _forumOkAt = DateTime.now();
      return;
    }

    // 只給很短的寬限。真的是挑戰的話早點叫出驗證頁讓使用者看著它解，
    // 比讓他對著空白轉圈圈好得多；而如果只是還在載入，驗證頁會在載完的
    // 瞬間自己關掉，等於沒有代價。
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (await _isForum(c)) {
        _forumOkAt = DateTime.now();
        return;
      }
    }
    _forumOkAt = null;
    throw const CloudflareException(_needSolve);
  }

  /// 目前頁面是不是真的論壇（而不是挑戰頁或錯誤頁）
  Future<bool> _isForum(WebViewController c) async {
    try {
      final r = await c.runJavaScriptReturningResult(probeJs);
      return r.toString().replaceAll('"', '') == 'forum';
    } catch (_) {
      return false;
    }
  }

  /// 探測目前頁面：`challenge`（攔截頁）／`forum`（論壇）／`other`。
  ///
  /// 驗證頁也用同一支，兩邊分開寫會慢慢長歪。
  ///
  /// **兩個踩過的坑：**
  /// 1. 不能拿 `challenge-platform` 當挑戰頁的依據。Cloudflare 開啟
  ///    JS Detections 時會把 `/cdn-cgi/challenge-platform/scripts/jsd/main.js`
  ///    注入到**每一個正常頁面**——拿它判斷會把整個論壇都當成挑戰頁。
  ///    `_cf_chl_opt` 才是攔截頁專屬的。
  /// 2. 不能用 `#hd`／`#nv`／`.bm`／`#ft` 認論壇，**那些是桌面版的選擇器**，
  ///    手機模板一個都沒有（實測樣本裡全是 0），所以永遠判不出 forum。
  ///    手機版頁面裡一定有大量指向 forum.php／home.php 的連結。
  static const probeJs = '''
(function () {
  var h = document.documentElement ? document.documentElement.innerHTML : '';
  // 攔截頁的特徵。新的 Turnstile 外掛回 200 而且沒有 Cloudflare 的標記，
  // 只能靠這幾個字串認；舊的也一起留著。
  if (h.indexOf('challenges.cloudflare.com/turnstile') >= 0 ||
      h.indexOf('dev8133_cloudflare') >= 0 ||
      h.indexOf('_cf_chl_opt') >= 0) {
    return 'challenge';
  }
  return document.querySelector(
      'a[href*="forum.php"], a[href*="home.php"], #postlist') ? 'forum' : 'other';
})()
''';

  void _onMessage(JavaScriptMessage m) {
    try {
      final data = json.decode(m.message) as Map<String, dynamic>;
      final c = _pending.remove(data['id'] as int);
      if (c == null || c.isCompleted) return;
      if (data['ok'] == true) {
        c.complete(data['body'] as String? ?? '');
      } else {
        // JS 的錯誤字串直接丟給使用者會變成「TypeError: Load failed」
        // 這種看不懂的東西，換成人話。
        c.completeError(DiscuzException(_friendly('${data['error'] ?? ''}')));
      }
    } catch (_) {
      // 壞掉的訊息就讓那個請求自己逾時，不要影響其他還在等的
    }
  }

  /// 用 WebView 抓一個網址。[form] 有值時送 POST（表單編碼，跟論壇一致）。
  Future<String> fetch(String url, {Map<String, String>? form}) async {
    final body = await _run(url, form: form, jsFunction: '__gmFetch');
    // 這個隱形的 WebView 自己也可能被挑戰。拿回挑戰頁的 HTML 去餵解析器
    // 只會得到一片空白，所以要認出來、交給呼叫端去請使用者解一次。
    if (looksLikeChallenge(body)) throw const CloudflareException(_needSolve);
    return body;
  }

  /// 同時最多幾個請求在 WebView 裡跑。
  ///
  /// 一頁幾十張圖全部併發的話，瀏覽器本身的同源連線數會排隊，JS 通道也會
  /// 塞住，反而整批逾時。排隊反而比較快，也比較不會誤判。
  static const _maxInFlight = 4;
  int _inFlight = 0;
  final _queue = <Completer<void>>[];

  Future<void> _acquire() async {
    if (_inFlight < _maxInFlight) {
      _inFlight++;
      return;
    }
    final wait = Completer<void>();
    _queue.add(wait);
    await wait.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _inFlight--;
    }
  }

  Future<String> _run(
    String url, {
    Map<String, String>? form,
    required String jsFunction,
  }) async {
    await _ensureReady();
    await _acquire();
    try {
      return await _send(url, form: form, jsFunction: jsFunction);
    } finally {
      _release();
    }
  }

  Future<String> _send(
    String url, {
    Map<String, String>? form,
    required String jsFunction,
  }) async {
    if (ready.value == null) throw const DiscuzException('瀏覽器傳輸沒有就緒');
    final c = await _viewFor(url);
    final isMain = identical(c, ready.value);

    final id = ++_seq;
    final completer = Completer<String>();
    _pending[id] = completer;

    try {
      // 只有論壇本體那顆要確認停在論壇上；圖片子網域那顆載的就是圖片來源
      if (isMain) await _ensureOnForum(c);
      // 每次都重新注入：頁面一導覽 JS 環境就沒了，而挑戰頁本身就會導覽。
      // 這段很短，重覆執行的成本可以忽略。
      await c.runJavaScript(_injectedJs);
      await c.runJavaScript(
        'window.$jsFunction(${json.encode({'id': id, 'url': url, 'form': form, 'channel': _channel})})',
      );
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pending.remove(id);
        throw const DiscuzException('瀏覽器取得逾時');
      },
    );
  }

  static const _needSolve = '需要先通過論壇的安全驗證';

  static String _friendly(String jsError) {
    if (jsError.contains('Load failed') || jsError.contains('NetworkError')) {
      return '連線中斷，請重試';
    }
    return jsError.isEmpty ? '取得內容失敗' : '取得內容失敗：$jsError';
  }

  /// App 從背景回來時呼叫。
  ///
  /// 掛在背景太久，iOS 會把 WebView 的內容清掉或讓 Cloudflare 的通行證過期，
  /// 回來之後頁面已經不是論壇了。不重新載入的話每個請求都會失敗，而且因為
  /// 那不是「新的挑戰」，驗證頁也不會跳出來——實機症狀是只能重開 App。
  Future<void> onResume() async {
    _forumOkAt = null;
    final c = ready.value;
    if (c == null) return;
    // **無條件重載，不要先探測。**
    //
    // 背景很久之後，WebView 上還留著背景前渲染好的舊論壇頁面——DOM 裡有
    // 論壇連結，探測會說「是論壇」，於是我們以為一切正常。但那頁的連線
    // 早就過期了，真的發請求還是失敗。舊畫面看起來對，不代表它還能用。
    try {
      await c.reload();
    } catch (_) {
      // 重載失敗就讓下一個請求走正常的挑戰流程
    }
  }

  /// 這段 HTML 是不是 Cloudflare 的挑戰頁。
  ///
  /// 走 WebView 時拿不到狀態碼與標頭（`fetch()` 只回文字），
  /// 只能比對挑戰頁的內文特徵。
  /// 這段 HTML 是不是 Cloudflare 的攔截頁。
  ///
  /// **不能比對 `challenge-platform`**：Cloudflare 開啟 JS Detections 時會把
  /// 那支腳本注入到每一個正常頁面，比對它會讓每一頁論壇內容都被當成挑戰，
  /// 於是驗證頁不斷跳出、解了也沒用——實機上就是這個症狀。
  /// `_cf_chl_opt` 是攔截頁才有的設定物件。
  /// 判斷交給共用層（`gm_api` 的 `isChallengeHtml`）——資料層與這裡各寫
  /// 一份的話，論壇換一次驗證方式就要修兩個地方，而且一定會漏掉一個。
  static bool looksLikeChallenge(String html) => isChallengeHtml(html);

  /// 用 WebView 抓一張圖。
  ///
  /// 圖片走的是 Flutter 自己的 HTTP 堆疊（`Image.network` /
  /// `CachedNetworkImage`），完全繞過這裡——所以 Cloudflare 擋著時，
  /// 文字內容進得來、圖片卻整片載入失敗（子版塊圖示、帖子圖片都是）。
  ///
  /// JS 通道只能傳字串，所以在頁面裡把 blob 轉成 data URL 再帶回來，
  /// 這邊解 base64。會膨脹三分之一，但這只是 Cloudflare 擋著時的後備。
  Future<Uint8List> fetchBytes(String url) async {
    try {
      return _decodeDataUrl(await _run(url, jsFunction: '__gmBytes'));
    } catch (_) {
      // 帖子裡的圖是 www 的 `forum.php?mod=image&aid=…`，它會 302 轉到
      // img 子網域。`fetch` 跟著跨來源的轉址時會被 CORS 擋掉，而且拿不到
      // 轉址目標——但**導覽可以**：讓 WebView 直接開那個網址，跟完轉址後
      // 文件的 origin 就落在圖片那一邊，這時再 fetch(location.href) 就同源了。
      return _fetchByNavigating(url);
    }
  }

  Uint8List _decodeDataUrl(String raw) {
    final i = raw.indexOf(',');
    if (!raw.startsWith('data:') || i < 0) {
      throw const DiscuzException('圖片取得失敗');
    }
    return base64Decode(raw.substring(i + 1));
  }

  /// 一次只讓一張圖用導覽的方式抓——它會把 WebView 整個帶走，不能並行。
  Future<void>? _navLock;

  Future<Uint8List> _fetchByNavigating(String url) async {
    while (_navLock != null) {
      await _navLock;
    }
    final done = Completer<void>();
    _navLock = done.future;
    try {
      return await _navigateAndRead(url);
    } finally {
      done.complete();
      _navLock = null;
    }
  }

  /// 導覽專用的 WebView。
  ///
  /// **不能跟抓圖那顆共用**：導覽會把整個頁面帶走，其他正在用同一顆
  /// WebView `fetch()` 的圖片會當場斷掉——實機症狀是「有些版塊圖示出得來、
  /// 有些出不來」，而且每次失敗的都不一樣。
  WebViewController? _navView;

  Future<Uint8List> _navigateAndRead(String url) async {
    var c = _navView;
    if (c == null) {
      c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(Api.userAgent)
        ..addJavaScriptChannel(_channel, onMessageReceived: _onMessage);
      _navView = c;
      _byOrigin['__nav'] = c; // 掛上畫面，JS 才跑得動
      origins.value++;
    }

    final loaded = Completer<void>();
    c.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onWebResourceError: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await c.loadRequest(Uri.parse(url));
    await loaded.future.timeout(const Duration(seconds: 25), onTimeout: () {});

    final id = ++_seq;
    final completer = Completer<String>();
    _pending[id] = completer;
    await c.runJavaScript(_injectedJs);
    // 用 location.href：跟完轉址之後那才是真正的圖片網址，而且同源
    await c.runJavaScript(
      'window.__gmBytes({id:$id,url:location.href,'
      'channel:"$_channel"})',
    );

    final raw = await completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _pending.remove(id);
        throw const DiscuzException('圖片取得逾時');
      },
    );
    return _decodeDataUrl(raw);
  }


  static const _injectedJs = '''
window.__gmFetch = function (a) {
  var opt = { credentials: 'include', redirect: 'follow' };
  if (a.form) {
    opt.method = 'POST';
    opt.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    var b = new URLSearchParams();
    for (var k in a.form) { b.append(k, a.form[k]); }
    opt.body = b.toString();
  }
  fetch(a.url, opt)
    .then(function (r) { return r.text(); })
    .then(function (t) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: true, body: t }));
    })
    .catch(function (e) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: false, error: String(e) }));
    });
};

window.__gmBytes = function (a) {
  fetch(a.url, { credentials: 'include', redirect: 'follow' })
    .then(function (r) { return r.blob(); })
    .then(function (b) {
      return new Promise(function (res, rej) {
        var fr = new FileReader();
        fr.onload = function () { res(fr.result); };
        fr.onerror = function () { rej(new Error('read failed')); };
        fr.readAsDataURL(b);
      });
    })
    .then(function (d) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: true, body: d }));
    })
    .catch(function (e) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: false, error: String(e) }));
    });
};
''';

  /// 掛在畫面上的宿主。
  ///
  /// **必須真的在 widget 樹裡**——iOS 的 WKWebView 不在畫面上時
  /// JavaScript 會被節流甚至完全不跑。
  ///
  /// 用 `Opacity(0)` 而不是 1×1 或 `Offstage`：Cloudflare 的挑戰會量視窗
  /// 尺寸當指紋的一部分，1×1 的瀏覽器很可疑，而且真要點「我是人類」時
  /// 也沒地方可點。透明度 0 的話版面照排、JS 照跑，只是看不見。
  /// 掛在畫面上的宿主。
  ///
  /// **必須真的在 widget 樹裡**——iOS 的 WKWebView 不在畫面上時
  /// JavaScript 會被節流甚至完全不跑。
  ///
  /// 用 `Opacity(0)` 而不是 1×1 或 `Offstage`：Cloudflare 的挑戰會量視窗
  /// 尺寸當指紋的一部分，1×1 的瀏覽器很可疑，而且真要點「我是人類」時
  /// 也沒地方可點。透明度 0 的話版面照排、JS 照跑，只是看不見。
  Widget host() => ValueListenableBuilder<bool>(
    valueListenable: presenting,
    builder: (_, showing, _) => ValueListenableBuilder<int>(
      valueListenable: origins,
      builder: (_, _, _) => Stack(
        children: [
          // 驗證頁正拿著主 WebView 時這裡要讓位——
          // 一個 controller 同時只能掛在一個 WebViewWidget 上
          if (!showing) _hidden(ready.value),
          for (final c in _byOrigin.values) _hidden(c),
        ],
      ),
    ),
  );

  Widget _hidden(WebViewController? c) => c == null
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: SizedBox(
              width: 360,
              height: 640,
              child: WebViewWidget(controller: c),
            ),
          ),
        );
}
