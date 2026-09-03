import 'package:gm_api/http.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

/// 論壇的透明轉發。
///
/// **為什麼需要**：Flutter 網頁版跑在瀏覽器裡，瀏覽器不准跨網域打論壇——
/// 論壇一個 CORS 標頭都沒送。所以整個 App 改成打自己網站上的 `/gm/...`，
/// 由這裡代打論壇再把結果原樣送回去。
///
/// **為什麼要同源**：網頁版和轉發路徑放在同一個網域，登入 cookie 就由瀏覽器
/// 自己保管、自己帶——不必自己實作 cookie jar，也不用處理 CORS 的
/// credentials 那一整套麻煩。
///
/// 這裡刻意**不碰內容**：HTML 原樣回去，讓瀏覽器裡那 6000 多行 gm_api
/// 照常解析。頁面裡的相對網址會自然落在 `/gm/` 底下，圖片也一樣。
class ForumProxy {
  ForumProxy({http.Client? client, this.prefix = '/gm'})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 掛在哪個路徑底下
  final String prefix;

  /// 這些標頭不能原樣轉——連線層自己會處理，照抄會壞掉
  static const _skipRequest = {
    'host', 'connection', 'content-length', 'accept-encoding',
    'origin', 'referer', 'cookie',
  };
  static const _skipResponse = {
    'content-encoding', 'content-length', 'transfer-encoding',
    'connection', 'set-cookie', 'strict-transport-security',
    'content-security-policy', 'x-frame-options',
  };

  Future<Response> handle(Request request) async {
    final rest = request.url.path;
    // ⚠️ 一定要用**原始的 query 字串**，不能用 queryParameters 重建。
    // queryParameters 是 Map，存不下重複的 key——而論壇有些網址就是會帶
    // 重複參數（例如 `...&mobile=no&mobile=2`，兩個 mobile）。用 Map 會
    // 只留最後一個，論壇因此回了不同的模板，解析器就什麼都抓不到
    // （記錄廣場整頁空白就是這樣來的）。
    final query = request.url.query;
    final target = Uri.parse(
        '$kForumOrigin/$rest${query.isEmpty ? '' : '?$query'}');

    final outgoing = http.Request(request.method, target)
      ..followRedirects = false;

    request.headers.forEach((k, v) {
      if (!_skipRequest.contains(k.toLowerCase())) outgoing.headers[k] = v;
    });
    // 論壇會看 Referer 決定要不要收表單，補成它自己的網址
    outgoing.headers['referer'] = '$kForumOrigin/forum.php?mobile=2';
    outgoing.headers['origin'] = kForumOrigin;

    // 只轉論壇的 cookie，我們自己的 session token 不要送出去
    final cookie = request.headers['cookie'];
    if (cookie != null && cookie.isNotEmpty) {
      final forwarded = cookie
          .split(';')
          .where((c) => !c.trimLeft().startsWith('gm_session='))
          .join(';');
      if (forwarded.trim().isNotEmpty) outgoing.headers['cookie'] = forwarded;
    }

    if (request.method == 'POST' || request.method == 'PUT') {
      outgoing.bodyBytes = await request.read()
          .expand((chunk) => chunk).toList();
    }

    final streamed = await _client.send(outgoing);
    final body = await streamed.stream.toBytes();

    final headers = <String, Object>{};
    streamed.headers.forEach((k, v) {
      if (!_skipResponse.contains(k.toLowerCase())) headers[k] = v;
    });

    // Set-Cookie 要把 Domain 拔掉，讓它落在我們自己的網域上；
    // 留著 .gamemale.com 的話瀏覽器會直接丟棄整個 cookie。
    final cookies = _setCookies(streamed);
    if (cookies.isNotEmpty) headers['set-cookie'] = cookies;

    // 論壇的轉址是指向它自己的網址，要改寫成我們的路徑，
    // 不然瀏覽器會跳出去、然後撞 CORS。
    final location = streamed.headers['location'];
    if (location != null) {
      headers['location'] = _rewriteLocation(location);
    }

    return Response(streamed.statusCode, body: body, headers: headers);
  }

  List<String> _setCookies(http.StreamedResponse res) {
    // http 套件會把多個 Set-Cookie 併成一個字串，要照 cookie 的邊界拆回來。
    // 不能直接用逗號切——Expires 裡本來就有逗號（Wed, 01 Sep ...）。
    final raw = res.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return const [];
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] == ',' &&
          i + 1 < raw.length &&
          RegExp(r'^\s*[A-Za-z0-9_\-]+=').hasMatch(raw.substring(i + 1))) {
        parts.add(raw.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(raw.substring(start));
    return [
      for (final p in parts)
        p
            .trim()
            // Domain 指向論壇的話瀏覽器會整條丟掉
            .replaceAll(RegExp(r';\s*[Dd]omain=[^;]*'), '')
            // Path 一定要放成根目錄，**不能收在 $prefix 底下**。
            // 收在 /gm 的話瀏覽器只會把論壇 cookie 送給 /gm/*，
            // 我們自己的 /api/* 就收不到——網頁版要綁推播時，伺服器
            // 會看不到登入狀態，回一句「請先登入」而使用者明明登入著。
            .replaceAll(RegExp(r';\s*[Pp]ath=[^;]*'), '; Path=/')
    ];
  }

  String _rewriteLocation(String location) {
    if (location.startsWith(kForumOrigin)) {
      return '$prefix${location.substring(kForumOrigin.length)}';
    }
    if (location.startsWith('http://') || location.startsWith('https://')) {
      // 轉去站外就讓它去，不要硬拉進代理
      return location;
    }
    return '$prefix/${location.replaceFirst(RegExp(r'^/'), '')}';
  }

  void close() => _client.close();
}
