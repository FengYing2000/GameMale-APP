import 'dart:convert';
import 'dart:io';

import 'package:gm_server/asset_guard.dart';
import 'package:gm_server/forum_proxy.dart';
import 'package:gm_api/http.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

/// GameMale 網頁版的後端。
///
/// 它只做三件事，全部都是為了讓瀏覽器裡的 Flutter 網頁版能正常瀏覽論壇：
///
///   1. **掛靜態檔**：`flutter build web` 的產出。
///   2. **`/gm` 論壇轉發**：瀏覽器不准跨網域打論壇（論壇一個 CORS 標頭
///      都沒送）。同源之後登入 cookie 也由瀏覽器自己保管，不必自己實作
///      cookie jar，伺服器上**不留任何帳號資料**。
///   3. **`/gmimg` 圖片代理**：帖子裡的圖常放在沒送 CORS 的第三方圖床，
///      而 App 是把圖讀進 canvas 的，跨網域讀像素會被擋掉。
///
/// 這裡**沒有**推播通知、沒有輪詢、沒有帳號儲存——那套整個移除了。
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final appRoot = env['APP_ROOT'] ?? '../../build/web';

  // 抓圖用的 client（公開資源，不帶任何登入狀態）
  final assetClient = http.Client();

  Response bad(String message, [int code = 400]) => Response(
        code,
        body: json.encode({'error': message}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  final router = Router()
    // ── 圖片代理 ───────────────────────────────────────────────
    ..get('/gmimg', (Request r) async {
      final raw = r.url.queryParameters['u'] ?? '';
      final uri = Uri.tryParse(raw);
      // 帖子裡的圖常常放在第三方圖床，而那些幾乎都沒送 CORS 標頭，
      // 所以主機不能只開白名單。改成「任何主機都代理，但只准圖片」，
      // 並擋掉會打到內網的位址——不然這就變成別人可以拿來探測這台機器
      // 內部服務的跳板（SSRF）。
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return bad('只接受 http/https 的圖片網址');
      }
      if (isPrivateHost(uri.host)) {
        return bad('不代理內網位址');
      }
      try {
        final res = await assetClient.get(uri, headers: {
          'User-Agent': Api.userAgent,
          // 有些圖床會擋空 Referer，帶論壇的比較不會被拒
          'Referer': '$kForumOrigin/',
        });
        if (res.statusCode >= 400) return Response.notFound('');

        final type = res.headers['content-type'] ?? '';
        // 只回圖片。少了這道，這支就成了萬用的內容代理。
        if (!isImageType(type)) return bad('這個網址不是圖片');
        if (res.bodyBytes.length > kMaxAssetBytes) return bad('圖片太大');

        return Response.ok(res.bodyBytes, headers: {
          'content-type': type,
          'cache-control': 'public, max-age=604800',
        });
      } catch (_) {
        return Response.notFound('');
      }
    });

  // 論壇轉發：讓瀏覽器裡的 Flutter 網頁版能打到論壇（它自己不准跨網域）
  final proxy = ForumProxy();
  Handler withProxy(Handler inner) => (Request r) {
        if (r.url.path == 'gm' || r.url.path.startsWith('gm/')) {
          return proxy.handle(r.change(path: 'gm'));
        }
        return inner(r);
      };

  final site = _withCacheHeaders(createStaticHandler(
      appRoot,
      defaultDocument: 'index.html',
      useHeaderBytesForContentType: true));

  final handler = withProxy(Cascade().add(router.call).add(site).handler);

  final server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(handler),
    InternetAddress.anyIPv4,
    port,
  );

  stdout.writeln('GameMale 網頁版後端啟動於 '
      'http://${server.address.host}:${server.port}');
  stdout.writeln(Directory(appRoot).existsSync()
      ? 'Flutter 網頁版：已掛載（$appRoot）'
      : '⚠ 找不到 $appRoot —— 先跑 flutter build web');
}

/// 靜態檔的快取策略。
///
/// **為什麼一定要管**：Flutter 網頁版的 main.dart.js／flutter_bootstrap.js
/// 檔名是固定的、不帶內容雜湊。若不送快取標頭，瀏覽器會用自己的啟發式
/// 規則決定重用多久——結果就是每次部署完，使用者手上還是舊程式碼，
/// 修好的東西看起來像沒修好。（這件事實際害我們來回除錯了好幾輪。）
///
/// 作法：會變動的入口檔一律 no-cache（仍會走 304，不會真的重下載全部），
/// 帶版本路徑或本來就不會變的資源（canvaskit、字型、圖示）給長快取。
Handler _withCacheHeaders(Handler inner) => (Request request) async {
      final res = await inner(request);
      final path = request.url.path;

      // 中文字體檔名帶內容雜湊（gm-cjk-<hash>.ttf），內容改了檔名就會變，
      // 所以可以給最強的快取。它有 4.7 MB（壓縮後），而且第一幀要等它，
      // 讓它變成真正的一次性成本很重要。
      final hashed = path.startsWith('fonts/');
      final immutable = path.startsWith('canvaskit/') ||
          path.startsWith('assets/') ||
          path.startsWith('icons/');

      return res.change(headers: {
        'cache-control': hashed
            ? 'public, max-age=31536000, immutable'
            : immutable
                ? 'public, max-age=604800'
                : 'no-cache, must-revalidate',
      });
    };
