import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

const String kOrigin = 'https://www.gamemale.com';

const String _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

/// 論壇連線層。
///
/// 和 Capacitor 版最大的差別：iOS 那邊 cookie 由系統的 URLSession 保管，
/// 這裡得自己用 PersistCookieJar 落地，否則每次冷啟動都要重新登入。
class Api {
  Api._();
  static final Api instance = Api._();

  late final Dio _dio;
  late final CookieJar _jar;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    // 測試環境沒有 path_provider 外掛，退回記憶體 cookie jar，
    // 這樣端對端測試才跑得起來，正式環境也不會因為取不到目錄就整個掛掉。
    try {
      final dir = await getApplicationSupportDirectory();
      _jar = PersistCookieJar(storage: FileStorage('${dir.path}/cookies'));
    } catch (_) {
      // 不要退回 PersistCookieJar()——它預設會在工作目錄建 .cookies 資料夾
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

  /// 補上 mobile=2，Discuz 才會回手機版模板
  static String mobileUrl(String path) {
    var p = path.startsWith('/') ? path.substring(1) : path;
    if (!RegExp(r'[?&]mobile=2(&|$)').hasMatch(p)) {
      p += '${p.contains('?') ? '&' : '?'}mobile=2';
    }
    return '/$p';
  }

  Future<String> get(String path, {bool followInterstitial = true}) async {
    await init();
    try {
      final res = await _dio.get<String>(
        mobileUrl(path),
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
    var target = m.group(1)!.replaceAll('&amp;', '&');
    if (target.startsWith(kOrigin)) {
      target = target.substring(kOrigin.length);
    } else if (target.startsWith('http')) {
      return null;   // 指到站外就不跟了
    }
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
        desktop ? '/${path.replaceFirst(RegExp(r'^/'), '')}' : mobileUrl(path),
        data: data,
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      _guard(res.statusCode);
      return res.data ?? '';
    } on DioException catch (e) {
      throw DiscuzException('送出失敗：${_reason(e)}');
    }
  }

  /// 已經編碼好的表單字串（投票的 pollanswers[] 是陣列，用 Map 帶不過去）
  Future<String> postRaw(String path, String body) async {
    await init();
    try {
      final res = await _dio.post<String>(
        mobileUrl(path),
        data: body,
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      _guard(res.statusCode);
      return res.data ?? '';
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
  static Map<String, String> get imageHeaders => const {
        'User-Agent': _ua,
        'Referer': '$kOrigin/forum.php?mobile=2',
      };

  /// 讀出名稱以某段字尾結束的 cookie（Discuz 的 cookie 都有站台專屬前綴）
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

/// 把頁面裡的相對網址轉成絕對網址
String absolute(String? u) {
  if (u == null) return '';
  var s = u.trim().replaceAll('&amp;', '&');
  if (s.isEmpty) return '';
  if (s.startsWith('//')) return 'https:$s';
  if (s.startsWith('http://') || s.startsWith('https://')) return s;
  if (s.startsWith('data:')) return s;
  s = s.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'^/'), '');
  return '$kOrigin/$s';
}

String avatarUrl(int uid, {String size = 'middle'}) =>
    '$kOrigin/uc_server/avatar.php?uid=$uid&size=$size';
