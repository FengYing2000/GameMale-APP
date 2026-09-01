import 'dart:convert';
import 'dart:io';

import 'package:gm_server/accounts.dart';
import 'package:gm_server/forum.dart';
import 'package:gm_server/poller.dart';
import 'package:gm_server/push_client.dart';
import 'package:gm_server/secret_box.dart';
import 'package:gm_server/vapid.dart';
import 'package:gm_server/webpush.dart';
import 'package:gm_api/discuz.dart' as api;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final vapidKey = env['VAPID_PRIVATE_KEY'];
  if (vapidKey == null || vapidKey.isEmpty) {
    stderr.writeln('沒有設 VAPID_PRIVATE_KEY。先跑：');
    stderr.writeln('  dart run bin/vapid_keygen.dart');
    exit(1);
  }
  final secretKey = env['SECRET_KEY'];
  if (secretKey == null || secretKey.isEmpty) {
    stderr.writeln('沒有設 SECRET_KEY（用來加密論壇 cookie）。先跑：');
    stderr.writeln('  dart run bin/secret_keygen.dart');
    exit(1);
  }

  final keys = VapidKeys.fromPrivateKey(vapidKey);
  final subject = env['VAPID_SUBJECT'] ?? 'mailto:admin@example.com';
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final webRoot = env['WEB_ROOT'] ?? '../web';
  final assetDir = env['ASSET_DIR'] ?? '../../assets';
  final pollMinutes = int.tryParse(env['POLL_MINUTES'] ?? '') ?? 5;

  await installServerBindings(assetDir: assetDir);

  final store = AccountStore(
    File(env['DATA_FILE'] ?? 'data/accounts.json'),
    SecretBox.fromBase64(secretKey),
  );
  await store.load();

  final push = PushClient(keys: keys, subject: subject);
  final logins = LoginSessions();
  final poller = Poller(
    store: store,
    push: push,
    interval: Duration(minutes: pollMinutes),
  );

  Response ok(Object body) => Response.ok(
        json.encode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  Response bad(String message, [int code = 400]) => Response(
        code,
        body: json.encode({'error': message}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Account? whoIs(Request r) {
    final auth = r.headers['authorization'] ?? '';
    if (!auth.startsWith('Bearer ')) return null;
    return store.byToken(auth.substring(7));
  }

  Future<Map<String, dynamic>> bodyOf(Request r) async {
    final raw = await r.readAsString();
    if (raw.isEmpty) return {};
    return (json.decode(raw) as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> stateOf(Account a) => {
        'username': a.username,
        'cookieStatus': a.cookieStatus,
        'autoSign': a.autoSign,
        'signReminderAt': a.signReminderAt,
        'notifyNotice': a.notifyNotice,
        'notifyPm': a.notifyPm,
        'notice': a.lastNotice,
        'pm': a.lastPm,
        'lastSignDate': a.lastSignDate,
        'lastCheckedAt': a.lastCheckedAt,
        'devices': a.subscriptions.length,
      };

  final router = Router()
    ..get('/api/config', (Request r) => ok({
          'vapidPublicKey': keys.publicKeyBase64,
          'pollMinutes': pollMinutes,
        }))

    // ── 登入（兩步：先取表單，再送出）──────────────────────────
    ..post('/api/login/begin', (Request r) async {
      try {
        final s = await logins.begin();
        return ok({
          'id': s.id,
          'needSeccode': s.meta.needSeccode,
          'captcha': s.meta.seccodeImage == null
              ? null
              : 'data:image/png;base64,${base64.encode(s.meta.seccodeImage!)}',
          'questions': [
            for (final q in s.meta.questions) {'id': q.id, 'name': q.name}
          ],
        });
      } catch (e) {
        return bad('連不上論壇的登入頁：$e', 502);
      }
    })
    ..post('/api/login/finish', (Request r) async {
      final b = await bodyOf(r);
      final pending = logins.take(b['id'] as String? ?? '');
      if (pending == null) {
        return bad('登入階段已過期，請重新開始');
      }
      final username = (b['username'] as String? ?? '').trim();
      final password = b['password'] as String? ?? '';
      if (username.isEmpty || password.isEmpty) {
        return bad('帳號與密碼都要填');
      }

      final result = await asAccount(pending.api, () => api.login(
            username: username,
            password: password,
            meta: pending.meta,
            questionid: b['questionid'] as String? ?? '0',
            answer: b['answer'] as String? ?? '',
            seccode: b['seccode'] as String? ?? '',
          ));
      if (!result.ok) return bad(result.message, 401);

      // 只把登入後的 cookie 存起來——**密碼不留**，它從頭到尾
      // 只是轉手送去論壇，這裡不寫進任何檔案
      final account = await store.upsert(
        username: username,
        cookiePlain: await dumpCookies(pending.api),
      );
      final token = await store.issueToken(account);
      stdout.writeln('登入成功：$username');
      return ok({'token': token, 'account': stateOf(account)});
    })

    ..get('/api/me', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      return ok(stateOf(a));
    })

    ..post('/api/logout', (Request r) async {
      final auth = r.headers['authorization'] ?? '';
      if (auth.startsWith('Bearer ')) await store.revokeToken(auth.substring(7));
      return ok({'ok': true});
    })

    ..post('/api/settings', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      final b = await bodyOf(r);
      if (b['autoSign'] is bool) a.autoSign = b['autoSign'] as bool;
      if (b['notifyNotice'] is bool) a.notifyNotice = b['notifyNotice'] as bool;
      if (b['notifyPm'] is bool) a.notifyPm = b['notifyPm'] as bool;
      final at = b['signReminderAt'] as String?;
      if (at != null) {
        if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(at)) {
          return bad('提醒時間要是 HH:mm');
        }
        a.signReminderAt = at;
      }
      await store.flush();
      return ok(stateOf(a));
    })

    // ── 裝置訂閱 ─────────────────────────────────────────────
    ..post('/api/subscribe', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('要先登入才能綁定通知', 401);
      try {
        await store.addSubscription(a, PushSubscription.fromJson(await bodyOf(r)));
        return ok(stateOf(a));
      } on FormatException catch (e) {
        return bad(e.message);
      }
    })
    ..post('/api/unsubscribe', (Request r) async {
      final b = await bodyOf(r);
      final removed = await store.removeSubscription(b['endpoint'] as String? ?? '');
      return ok({'ok': removed});
    })

    // ── 測試與手動觸發 ───────────────────────────────────────
    ..post('/api/test-push', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      if (a.subscriptions.isEmpty) return ok({'sent': 0, 'note': '這個帳號還沒有綁定裝置'});
      var sent = 0;
      final results = <String, String>{};
      for (final sub in [...a.subscriptions]) {
        final res = await push.send(subscription: sub, payload: {
          'title': '推播測試',
          'body': '收到這則就表示通了 —— ${nowHhmmTaipei()}',
          'tag': 'test',
          'url': '/',
        });
        results[Uri.parse(sub.endpoint).host] = res.toString();
        if (res.ok) sent++;
        if (res.outcome == PushOutcome.gone) {
          await store.removeSubscription(sub.endpoint);
        }
      }
      return ok({'sent': sent, 'results': results});
    })
    ..post('/api/poll-now', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      await poller.tick();
      return ok(stateOf(a));
    });

  final handler = Cascade()
      .add(router.call)
      .add(createStaticHandler(webRoot,
          defaultDocument: 'index.html', useHeaderBytesForContentType: true))
      .handler;

  final server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(handler),
    InternetAddress.anyIPv4,
    port,
  );

  poller.start();

  stdout.writeln('GameMale PWA 後端啟動於 '
      'http://${server.address.host}:${server.port}');
  stdout.writeln('VAPID 公鑰：${keys.publicKeyBase64}');
  stdout.writeln('已有 ${store.length} 個帳號，每 $pollMinutes 分鐘輪詢一次');
}
