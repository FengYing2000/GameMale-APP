import 'dart:async';
import 'dart:convert';

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

  Future<void>? _booting;
  final _pending = <int, Completer<String>>{};
  int _seq = 0;

  /// 上次看到的頁面是不是挑戰頁。是的話下次取用前要先重新載入——
  /// 使用者在可見的驗證頁解完之後，這個隱形的還停在舊的挑戰頁上。
  bool _stuck = false;

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

    c.setNavigationDelegate(
      NavigationDelegate(
        // ⚠️ 不能在第一個 onPageFinished 就當作就緒。
        // Cloudflare 的挑戰頁自己也會觸發這個事件，那時候頁面上是挑戰
        // 不是論壇——直接去 fetch 只會拿回挑戰頁的 HTML。
        // 要等到頁面**真的是論壇**（挑戰解掉後 CF 會自己重新導向）。
        onPageFinished: (_) async {
          if (settled.isCompleted) return;
          if (await _isForum(c)) {
            _stuck = false;
            settled.complete();
          } else {
            _stuck = true;
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

    // 給挑戰自己解的時間。Cloudflare 的自動挑戰通常幾秒內就過，
    // 等太久只會讓使用者對著空白轉圈圈——解不掉就早點讓 fetch 拿回挑戰頁，
    // 由上層把可見的驗證頁叫出來（在那裡他看得到進度，也點得到按鈕）。
    await settled.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  }

  /// 目前頁面是不是真的論壇（而不是挑戰頁或錯誤頁）
  Future<bool> _isForum(WebViewController c) async {
    try {
      final r = await c.runJavaScriptReturningResult(_probeJs);
      return r.toString().replaceAll('"', '') == 'forum';
    } catch (_) {
      return false;
    }
  }

  static const _probeJs = '''
(function () {
  var h = document.documentElement ? document.documentElement.innerHTML : '';
  if (h.indexOf('challenge-platform') >= 0 || h.indexOf('_cf_chl_opt') >= 0) {
    return 'challenge';
  }
  return document.querySelector('#hd, #nv, .bm, #ft, #postlist') ? 'forum' : 'other';
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
    await _ensureReady();
    final c = ready.value;
    if (c == null) throw const DiscuzException('瀏覽器傳輸沒有就緒');

    final id = ++_seq;
    final completer = Completer<String>();
    _pending[id] = completer;

    try {
      // 上次停在挑戰頁的話先重新載入——使用者可能已經在可見的驗證頁解掉了，
      // 兩邊共用同一份 cookie store，重載就會拿到真的論壇頁。
      if (_stuck) {
        _stuck = false;
        await c.reload();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      // 每次都重新注入：頁面一導覽 JS 環境就沒了，而挑戰頁本身就會導覽。
      // 這段很短，重覆執行的成本可以忽略。
      await c.runJavaScript(_injectedJs);
      await c.runJavaScript(
        'window.__gmFetch(${json.encode({'id': id, 'url': url, 'form': form, 'channel': _channel})})',
      );
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    final body = await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pending.remove(id);
        throw const DiscuzException('瀏覽器取得逾時');
      },
    );

    // 這個隱形的 WebView 自己也可能被挑戰。拿回挑戰頁的 HTML 去餵解析器
    // 只會得到一片空白，所以要認出來、交給呼叫端去請使用者解一次。
    if (looksLikeChallenge(body)) {
      _stuck = true;
      throw const CloudflareException(_needSolve);
    }
    return body;
  }

  static const _needSolve = '需要先通過論壇的安全驗證';

  static String _friendly(String jsError) {
    if (jsError.contains('Load failed') || jsError.contains('NetworkError')) {
      return '連線中斷，請重試';
    }
    return jsError.isEmpty ? '取得內容失敗' : '取得內容失敗：$jsError';
  }

  /// 這段 HTML 是不是 Cloudflare 的挑戰頁。
  ///
  /// 走 WebView 時拿不到狀態碼與標頭（`fetch()` 只回文字），
  /// 只能比對挑戰頁的內文特徵。
  static bool looksLikeChallenge(String html) =>
      html.contains('cdn-cgi/challenge-platform') ||
      html.contains('cf-browser-verification') ||
      html.contains('_cf_chl_opt');

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
''';

  /// 掛在畫面上的宿主。
  ///
  /// **必須真的在 widget 樹裡**——iOS 的 WKWebView 不在畫面上時
  /// JavaScript 會被節流甚至完全不跑。
  ///
  /// 用 `Opacity(0)` 而不是 1×1 或 `Offstage`：Cloudflare 的挑戰會量視窗
  /// 尺寸當指紋的一部分，1×1 的瀏覽器很可疑，而且真要點「我是人類」時
  /// 也沒地方可點。透明度 0 的話版面照排、JS 照跑，只是看不見。
  Widget host() => ValueListenableBuilder<WebViewController?>(
    valueListenable: ready,
    builder: (_, c, _) => c == null
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
          ),
  );
}
