import 'dart:convert';
import 'dart:io';

import 'package:gm_server/push_client.dart';
import 'package:gm_server/store.dart';
import 'package:gm_server/vapid.dart';
import 'package:gm_server/webpush.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

/// 第一階段的目標只有一個：**證明 Web Push 在 iPhone 上真的會響**。
/// 論壇的東西還沒接進來，先把管道打通再說——推播不通的話，
/// 後面整個 PWA 都是白做的。
Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final privateKey = env['VAPID_PRIVATE_KEY'];
  if (privateKey == null || privateKey.isEmpty) {
    stderr.writeln('沒有設 VAPID_PRIVATE_KEY。先跑：');
    stderr.writeln('  dart run bin/vapid_keygen.dart');
    stderr.writeln('把印出來的那行存進 .env 或環境變數再啟動。');
    exit(1);
  }
  final keys = VapidKeys.fromPrivateKey(privateKey);
  final subject = env['VAPID_SUBJECT'] ?? 'mailto:admin@example.com';
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final webRoot = env['WEB_ROOT'] ?? '../web';

  final store = SubscriptionStore(File(env['DATA_FILE'] ?? 'data/subs.json'));
  await store.load();

  final push = PushClient(keys: keys, subject: subject);

  Response ok(Object body) => Response.ok(
        json.encode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  final api = Router()
    // 前端訂閱時要用的公鑰
    ..get('/api/config', (Request r) => ok({
          'vapidPublicKey': keys.publicKeyBase64,
          'subscribers': store.length,
        }))
    ..post('/api/subscribe', (Request r) async {
      final body = json.decode(await r.readAsString()) as Map<String, dynamic>;
      try {
        final sub = PushSubscription.fromJson(body);
        await store.add(sub);
        stdout.writeln('新訂閱：${_short(sub.endpoint)}（共 ${store.length} 筆）');
        return ok({'ok': true, 'subscribers': store.length});
      } on FormatException catch (e) {
        return Response.badRequest(
          body: json.encode({'error': e.message}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      } catch (e) {
        return Response.badRequest(
          body: json.encode({'error': '訂閱資料看不懂：$e'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    })
    ..post('/api/unsubscribe', (Request r) async {
      final body = json.decode(await r.readAsString()) as Map<String, dynamic>;
      final removed = await store.remove(body['endpoint'] as String? ?? '');
      return ok({'ok': removed, 'subscribers': store.length});
    })
    // 測試用：推給所有已訂閱的裝置
    ..post('/api/test-push', (Request r) async {
      if (store.length == 0) {
        return ok({'sent': 0, 'note': '還沒有任何裝置訂閱'});
      }
      final results = <String, String>{};
      var sent = 0;
      for (final sub in store.all) {
        final res = await push.send(
          subscription: sub,
          payload: {
            'title': 'GameMale',
            'body': '推播測試成功 —— ${DateTime.now().toString().substring(11, 19)}',
            'url': '/',
          },
        );
        results[_short(sub.endpoint)] = res.toString();
        if (res.ok) sent++;
        // 訂閱失效就順手清掉，不然每次都會失敗
        if (res.outcome == PushOutcome.gone) await store.remove(sub.endpoint);
      }
      stdout.writeln('測試推播：成功 $sent／${results.length}  $results');
      return ok({'sent': sent, 'results': results});
    });

  // API 找不到的路徑才交給靜態檔，這樣 /api/* 打錯不會回一個 HTML
  final handler = Cascade()
      .add(api.call)
      .add(createStaticHandler(webRoot,
          defaultDocument: 'index.html', useHeaderBytesForContentType: true))
      .handler;

  final server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(handler),
    InternetAddress.anyIPv4,
    port,
  );

  stdout.writeln('GameMale PWA 後端啟動於 http://${server.address.host}:${server.port}');
  stdout.writeln('VAPID 公鑰：${keys.publicKeyBase64}');
  stdout.writeln('已有 ${store.length} 筆訂閱');
}

String _short(String endpoint) {
  final uri = Uri.parse(endpoint);
  final tail = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  return '${uri.host}/…${tail.length > 8 ? tail.substring(tail.length - 8) : tail}';
}
