import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'models.dart';

/// 現在是不是跑在瀏覽器上。
///
/// gm_api 刻意不依賴 Flutter，所以用不了 `kIsWeb`——這是它背後同一招：
/// 編譯器會依可用的函式庫定義 `dart.library.*`。
const bool kIsWebPlatform = bool.fromEnvironment('dart.library.js_util');

/// 論壇的正式網址。用來判斷「這是不是站內連結」。
const String kForumOrigin = 'https://www.gamemale.com';

/// 實際要打的位址。
///
/// 原生版直連論壇。**網頁版不能直連**——瀏覽器不准跨網域打論壇
/// （論壇沒送任何 CORS 標頭），所以要指到自己網站上的轉發路徑，由伺服器代打。
/// 圖片、連結、請求全都經過 [absolute]／[avatarUrl]／[Api]，
/// 所以只要在啟動時改這一個變數，整批就會轉向。
///
/// 一定要在 [Api.init] 之前設定。
String kOrigin = kForumOrigin;

/// 網頁版專用：指向論壇的**絕對**網址要改走這個前綴的代理。
///
/// 論壇的圖片有不少放在 `img.gamemale.com`，那是另一個子網域，
/// [absolute] 不會動它。瀏覽器抓跨網域圖片時，CanvasKit 是用 fetch 讀進來
/// 再畫到 canvas 上，所以**一樣受 CORS 限制**——那些站台同樣沒送 CORS 標頭，
/// 圖就整片載不出來。
///
/// 設成類似 `/gmimg?u=` 之後，這類網址會被包成自家的代理路徑。
/// 空字串＝不改寫（原生版直連，不需要）。
String kAssetProxyPrefix = '';

/// 網頁版可以（也應該）走自家資源代理的圖片來源。
///
/// * 論壇自己的子網域：`img.gamemale.com` 之類，**完全沒送 CORS 標頭**，
///   不走代理的話 App 把圖讀進 canvas 一定失敗。
/// * 論壇拿來放表情符號的 CDN：雖然它有送 CORS，但走自家代理比較不會
///   受第三方 CDN 在當地連不連得上影響。
///
/// 這是白名單而不是萬用代理——只放行論壇實際會用到的來源。
bool _isProxyableAssetHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host == 'gamemale.com' || host.endsWith('.gamemale.com')) return true;
  return host.endsWith('jsdelivr.net');
}

const String _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

/// 論壇連線層。
///
/// 和 Capacitor 版最大的差別：iOS 那邊 cookie 由系統的 URLSession 保管，
/// 這裡得自己用 PersistCookieJar 落地，否則每次冷啟動都要重新登入。
class Api {
  Api._();

  static final Api _default = Api._();

  /// 目前這個 Zone 要用的連線。
  ///
  /// App 端永遠只有一個帳號，拿到的就是 [_default]，行為跟以前一樣。
  /// 伺服器要同時服務多個帳號，每個帳號的 cookie 與 formhash 都必須分開，
  /// 所以用 Zone 帶著走——見 [runAs]。這樣 6000 多行裡那些
  /// `Api.instance.xxx` 一行都不用改。
  static Api get instance => (Zone.current[#gmApi] as Api?) ?? _default;

  /// 另外開一條帶自己 cookie 的連線（伺服器每個帳號一條）
  static Future<Api> forAccount(CookieJar jar) async {
    final api = Api._();
    await api.init(jar: jar);
    return api;
  }

  /// 在 [api] 這條連線底下執行 [body]。
  ///
  /// 伺服器輪詢每個帳號時包一層，裡面所有 `Api.instance` 就會指到它。
  static Future<T> runAs<T>(Api api, Future<T> Function() body) =>
      runZoned(body, zoneValues: {#gmApi: api});

  /// 這條連線的 formhash。
  ///
  /// **綁 session，所以放在實例上而不是模組層**——多帳號共用一份的話，
  /// A 帳號的 hash 會被拿去送 B 帳號的請求，論壇會回「請重新登入」，
  /// 而且那種錯很難查。
  String? formhash;

  late final Dio _dio;
  late final CookieJar _jar;
  bool _ready = false;

  /// cookie 要存在哪，由呼叫端決定。
  ///
  /// 這個套件是純 Dart 的，不能用 path_provider（那是 Flutter 外掛）。
  /// Flutter App 在 main() 裡注入指向 app 支援目錄的 PersistCookieJar；
  /// 伺服器注入自己的路徑；測試不注入就用記憶體版。
  ///
  /// 一定要在 [init] 之前設定。
  static CookieJar Function()? cookieJarFactory;

  Future<void> init({CookieJar? jar}) async {
    if (_ready) return;

    try {
      _jar = jar ?? cookieJarFactory?.call() ?? CookieJar();
    } catch (_) {
      // 注入的那個建不起來（例如目錄沒權限）也不該讓整個 App 掛掉。
      // 不要退回 PersistCookieJar()——它預設會在工作目錄偷建 .cookies
      _jar = CookieJar();
    }

    _dio = Dio(BaseOptions(
      baseUrl: kOrigin,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-TW,zh;q=0.9,zh-CN;q=0.8',
        'Referer': '$kOrigin/forum.php?mobile=2',
      },
      // 4xx/5xx 自己判斷，不讓 dio 直接丟例外
      validateStatus: (s) => s != null && s < 500,
    ));

    _dio.interceptors.add(CookieManager(_jar));
    _ready = true;
  }

  /// 這條連線目前持有的 cookie。
  ///
  /// 伺服器登入完要把它存起來，下次輪詢直接用，不必再登入一次。
  /// App 端用不到——它的 cookie 由 PersistCookieJar 自己落地。
  Future<List<Cookie>> cookiesFor(Uri uri) async {
    await init();
    return _jar.loadForRequest(uri);
  }

  /// 補上 mobile=2，Discuz 才會回手機版模板
  static String mobileUrl(String path) {
    var p = path.startsWith('/') ? path.substring(1) : path;
    if (!RegExp(r'[?&]mobile=2(&|$)').hasMatch(p)) {
      p += '${p.contains('?') ? '&' : '?'}mobile=2';
    }
    return '/$p';
  }
  /// 桌面模板。光是不帶 mobile=2 沒用 —— Discuz 會看 User-Agent 自動轉手機版，
  /// 一定要明寫 mobile=no 才拿得到桌面版（個人資料的角色組／勳章只有桌面版有）
  static String desktopUrl(String path) {
    var p = path.startsWith('/') ? path.substring(1) : path;
    p = p.replaceAll(RegExp(r'[?&]mobile=(2|no)'), '');
    if (!p.contains('?') && p.contains('&')) p = p.replaceFirst('&', '?');
    p += '${p.contains('?') ? '&' : '?'}mobile=no';
    return '/$p';
  }


  /// desktop=true 取桌面模板（個人資料的擴展角色組、勳章等只有桌面版才有）
  Future<String> get(String path,
      {bool followInterstitial = true, bool desktop = false}) async {
    await init();
    try {
      final res = await _dio.get<String>(
        desktop ? desktopUrl(path) : mobileUrl(path),
        options: Options(responseType: ResponseType.plain),
      );
      _guard(res.statusCode);
      final body = res.data ?? '';

      // 有些模組沒有手機版，論壇會先丟一頁「您访问的页面无手机页面」，
      // 真正的內容在那頁的「继续访问」連結後面。自動跟過去，
      // 否則搜尋（日誌／相簿／群組／使用者）之類的功能全部拿到空白。
      if (followInterstitial) {
        final next = _interstitialTarget(body);
        if (next != null) return await get(next, followInterstitial: false);
      }
      return body;
    } on DioException catch (e) {
      throw DiscuzException('網路連線失敗：${_reason(e)}');
    }
  }

  static final _jumpLink =
      RegExp(r'<div class="jump_c">[\s\S]*?<a href="([^"]+)" class="mtn"');

  static String? _interstitialTarget(String html) {
    if (!html.contains('无手机页面') && !html.contains('無手機頁面')) return null;
    final m = _jumpLink.firstMatch(html);
    if (m == null) return null;

    // 提示頁給的是絕對網址，直接丟回 get() 會被接在 baseUrl 後面變成 /https://…
    //
    // **兩種來源都要認**：kOrigin 在網頁版是我們自己的轉發位址
    // （https://自家網域/gm），但頁面內容是論壇原樣吐回來的，裡面的連結
    // 一律是 https://www.gamemale.com/…。只比對 kOrigin 的話，網頁版會把
    // 它當成站外連結而不跟過去，結果拿到的是提示頁而不是內容——
    // 記錄廣場、搜尋、日誌、相簿、群組整片空白就是這樣來的。
    var target = m.group(1)!.replaceAll('&amp;', '&');
    target = _stripOrigin(target);
    if (target.startsWith('http')) return null; // 真的指到站外就不跟
    return target.replaceFirst(RegExp(r'^/'), '');
  }

  /// Discuz 的表單一律 application/x-www-form-urlencoded。
  ///
  /// desktop=true 時不加 mobile=2 —— 發文走桌面端點，
  /// 論壇的處理邏輯一樣，但外掛（勳章積分）掛在桌面流程上。
  Future<String> post(String path, Map<String, dynamic> form,
      {bool desktop = false}) async {
    await init();
    final data = <String, dynamic>{};
    form.forEach((k, v) {
      if (v != null) data[k] = v.toString();
    });
    try {
      final res = await _dio.post<String>(
        desktop ? desktopUrl(path) : mobileUrl(path),
        data: data,
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      _guard(res.statusCode);
      return await _afterPost(res, desktop: desktop);
    } on DioException catch (e) {
      throw DiscuzException('送出失敗：${_reason(e)}');
    }
  }

  /// Dart 的 HttpClient 只會自動跟隨 GET/HEAD 的轉址，POST 收到 302 就直接把
  /// 空 body 交回來（`member.php?mod=register` 就是這樣）。這裡手動補一次 GET。
  Future<String> _afterPost(Response<String> res, {required bool desktop}) async {
    final body = res.data ?? '';
    if (body.isNotEmpty) return body;

    final location = res.headers.value('location');
    if (location == null || location.isEmpty) return body;

    // 同上：論壇給的 Location 是它自己的網址，網頁版的 kOrigin 不是那個
    var target = _stripOrigin(location);
    if (target.startsWith('http')) return body;   // 轉去站外就不跟了
    return get(target.replaceFirst(RegExp(r'^/'), ''), desktop: desktop);
  }

  /// 已經編碼好的表單字串（投票的 pollanswers[] 是陣列，用 Map 帶不過去）
  Future<String> postRaw(String path, String body,
      {bool desktop = false}) async {
    await init();
    try {
      final res = await _dio.post<String>(
        desktop ? desktopUrl(path) : mobileUrl(path),
        data: body,
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      _guard(res.statusCode);
      return await _afterPost(res, desktop: desktop);
    } on DioException catch (e) {
      throw DiscuzException('送出失敗：${_reason(e)}');
    }
  }

  /// 驗證碼圖片必須帶著 session cookie 抓，所以走這裡而不是直接給 Image.network
  Future<Uint8List> getBytes(String path) async {
    await init();
    try {
      final res = await _dio.get<List<int>>(
        mobileUrl(path),
        options: Options(responseType: ResponseType.bytes),
      );
      _guard(res.statusCode);
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw DiscuzException('圖片載入失敗：${_reason(e)}');
    }
  }

  /// 抓任意絕對網址的二進位內容（圖片可能來自外站圖床）
  Future<Uint8List> getAbsoluteBytes(String url) async {
    await init();
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: imageHeaders,
        ),
      );
      _guard(res.statusCode);
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw DiscuzException('下載失敗：${_reason(e)}');
    }
  }

  /// 圖片走 Image.network / CachedNetworkImage 時要帶的標頭
  static Map<String, String> get imageHeaders => kIsWebPlatform
      // 瀏覽器**禁止**自訂 User-Agent 與 Referer（forbidden header names），
      // 帶了整個請求會直接失敗——圖片會全部載不出來，而且不會有錯誤訊息。
      // 網頁版的圖片本來就走 /gm 轉發，這兩個標頭由伺服器補。
      ? const <String, String>{}
      : {
          'User-Agent': _ua,
          'Referer': '$kOrigin/forum.php?mobile=2',
        };

  /// 讀出名稱以某段字尾結束的 cookie（Discuz 的 cookie 都有站台專屬前綴）
  /// 內建瀏覽器要用同一組 UA，不然論壇會給不一樣的模板
  static String get userAgent => _ua;

  /// 論壇的外掛頁面全都只有桌面模板。iPhone UA 會被自動導去
  /// 「無手機頁面」提示，所以網址一定要明帶 mobile=no
  static String desktopFullUrl(String path) => '$kOrigin${desktopUrl(path)}';

  /// 論壇目前的全部 cookie。內建瀏覽器要靠這個帶著登入狀態，
  /// 不然開出來是未登入的頁面，等於要再登入一次
  Future<List<({String name, String value})>> allCookies() async {
    await init();
    final cookies = await _jar.loadForRequest(Uri.parse(kOrigin));
    return [for (final c in cookies) (name: c.name, value: c.value)];
  }

  /// 把某個 cookie 清成空字串。
  ///
  /// 論壇的積分提示是靠 `<cookiepre>_creditnotice` 傳的，網頁版顯示完會
  /// 自己清掉；App 讀完卻沒清，結果每次用內建瀏覽器開論壇頁面，
  /// 都會再跳一次上一回操作的積分變化。
  Future<void> clearCookieEndingWith(String suffix) async {
    await init();
    final uri = Uri.parse(kOrigin);
    final cookies = await _jar.loadForRequest(uri);
    final keep = <Cookie>[];
    var found = false;
    for (final c in cookies) {
      if (c.name.endsWith(suffix)) {
        found = true;
        keep.add(Cookie(c.name, '')..path = '/');
      } else {
        keep.add(c);
      }
    }
    if (found) await _jar.saveFromResponse(uri, keep);
  }

  Future<String?> cookieEndingWith(String suffix) async {
    await init();
    final cookies = await _jar.loadForRequest(Uri.parse(kOrigin));
    for (final c in cookies) {
      if (c.name.endsWith(suffix)) return c.value;
    }
    return null;
  }

  Future<void> clearCookies() async {
    await init();
    await _jar.deleteAll();
  }

  /// 端對端測試用：直接灌入瀏覽器抓來的 cookie 字串
  Future<void> seedCookies(String cookieHeader) async {
    await init();
    final cookies = cookieHeader
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.contains('='))
        .map((s) {
          final i = s.indexOf('=');
          return Cookie(s.substring(0, i), s.substring(i + 1))
            ..domain = '.gamemale.com'
            ..path = '/';
        })
        .toList();
    await _jar.saveFromResponse(Uri.parse(kOrigin), cookies);
  }

  void _guard(int? status) {
    if (status != null && status >= 400) {
      throw DiscuzException('伺服器回應 $status', status);
    }
  }

  String _reason(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '連線逾時';
      case DioExceptionType.connectionError:
        return '無法連線到論壇';
      default:
        return e.message ?? '未知錯誤';
    }
  }
}

/// 去掉「自家位址」的前綴，留下站內路徑。
///
/// 要同時認 [kOrigin]（網頁版是自己的轉發位址）與 [kForumOrigin]
/// （論壇本尊，頁面內容裡的連結都用這個）。原生版兩者相同。
String _stripOrigin(String url) {
  if (url.startsWith(kOrigin)) return url.substring(kOrigin.length);
  if (url.startsWith(kForumOrigin)) return url.substring(kForumOrigin.length);
  return url;
}

/// 把頁面裡的相對網址轉成絕對網址
String absolute(String? u) {
  if (u == null) return '';
  var s = u.trim().replaceAll('&amp;', '&');
  if (s.isEmpty) return '';
  if (s.startsWith('data:')) return s;
  if (s.startsWith('//')) s = 'https:$s';

  if (s.startsWith('http://') || s.startsWith('https://')) {
    // 原生版直連論壇，絕對網址原樣用就好
    if (kOrigin == kForumOrigin) return s;

    final uri = Uri.tryParse(s);
    if (uri == null) return s;

    // 論壇**本站**的絕對網址 → 改成走 /gm 轉發。
    //
    // 這裡不能一律丟去圖片代理：absolute() 同時用在圖片**和連結**上，
    // 而連結（道具的使用／購買、收藏、群組管理…）會被當成請求路徑再打
    // 一次。丟進圖片代理的話那些路徑就變成 `/gmimg?u=…`，請求直接 404
    // ——「拿不到道具資訊：伺服器回應404」就是這樣來的。
    // /gm 轉發本來就能處理論壇本站的任何路徑，圖片與連結都適用。
    if (uri.host == Uri.parse(kForumOrigin).host) {
      return '$kOrigin${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
          '${uri.hasFragment ? '#${uri.fragment}' : ''}';
    }

    // 其他子網域（img.gamemale.com 之類）/gm 轉不到，而且只會是靜態
    // 資源，走圖片代理。
    if (kAssetProxyPrefix.isNotEmpty && _isProxyableAssetHost(s)) {
      return '$kAssetProxyPrefix${Uri.encodeComponent(s)}';
    }
    return s;
  }

  s = s.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'^/'), '');
  return '$kOrigin/$s';
}

String avatarUrl(int uid, {String size = 'middle'}) =>
    '$kOrigin/uc_server/avatar.php?uid=$uid&size=$size';
