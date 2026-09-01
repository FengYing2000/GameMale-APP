import 'dart:convert';
import 'dart:io';

import 'package:gm_server/accounts.dart';
import 'package:gm_server/forum.dart';
import 'package:gm_server/forum_proxy.dart';
import 'package:gm_server/json_api.dart';
import 'package:gm_server/poller.dart';
import 'package:gm_server/push_client.dart';
import 'package:gm_server/secret_box.dart';
import 'package:gm_server/vapid.dart';
import 'package:gm_server/webpush.dart';
import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

const _sessionCookie = 'gm_session';

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
  // Flutter 網頁版的產出（flutter build web）。放著就會被掛上去。
  final appRoot = env['APP_ROOT'] ?? '../../build/web';
  final assetDir = env['ASSET_DIR'] ?? '../../assets';
  final pollMinutes = int.tryParse(env['POLL_MINUTES'] ?? '') ?? 5;

  await installServerBindings(assetDir: assetDir);

  final store = AccountStore(
    File(env['DATA_FILE'] ?? 'data/accounts.json'),
    SecretBox.fromBase64(secretKey),
  );
  await store.load();

  final push = PushClient(keys: keys, subject: subject);
  // 抓論壇圖片用的 client（公開資源，不帶登入）
  final assetClient = http.Client();
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

  /// 認 cookie 為主、Bearer 為輔。
  ///
  /// **一定要有 cookie 這條路**：論壇圖片是用 <img> 載的，而 <img>
  /// 沒辦法帶 Authorization 標頭。把 token 塞進網址又會被寫進瀏覽器歷史
  /// 與伺服器日誌，所以走 HttpOnly cookie 讓瀏覽器自己帶。
  /// Bearer 留著給 curl 測試用。
  Account? whoIs(Request r) {
    final auth = r.headers['authorization'] ?? '';
    if (auth.startsWith('Bearer ')) return store.byToken(auth.substring(7));
    for (final part in (r.headers['cookie'] ?? '').split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0] == _sessionCookie) {
        return store.byToken(Uri.decodeComponent(kv[1]));
      }
    }
    return null;
  }

  /// SameSite=Lax 就夠了——這個站沒有跨站表單，Strict 會讓從通知點進來的
  /// 第一個請求帶不到 cookie。
  String sessionCookie(String token, {bool clear = false}) =>
      '$_sessionCookie=${clear ? '' : Uri.encodeComponent(token)}; '
      'HttpOnly; Secure; SameSite=Lax; Path=/; '
      'Max-Age=${clear ? 0 : 60 * 60 * 24 * 30}';

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

  /// 論壇相關的路徑共用：檢查登入、用這個帳號的 cookie 開連線、
  /// 把論壇那邊的錯誤翻成前端看得懂的回應。
  Future<Response> forum(
      Request r, Future<Object> Function(Api target) body) async {
    final a = whoIs(r);
    if (a == null) return bad('尚未登入', 401);
    if (a.cookieStatus == 'expired') {
      return bad('論壇的登入已過期，請重新登入', 401);
    }
    try {
      return ok(await body(await a.connect(store)));
    } on DiscuzException catch (e) {
      return bad('論壇回了錯誤：${e.message}', 502);
    } catch (e) {
      return bad('$e', 500);
    }
  }

  int intParam(Request r, String name, int fallback) =>
      int.tryParse(r.url.queryParameters[name] ?? '') ?? fallback;

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
      return Response.ok(
        json.encode({'account': stateOf(account)}),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'set-cookie': sessionCookie(token),
        },
      );
    })

    ..get('/api/me', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      return ok(stateOf(a));
    })

    ..post('/api/logout', (Request r) async {
      for (final part in (r.headers['cookie'] ?? '').split(';')) {
        final kv = part.trim().split('=');
        if (kv.length == 2 && kv[0] == _sessionCookie) {
          await store.revokeToken(Uri.decodeComponent(kv[1]));
        }
      }
      final auth = r.headers['authorization'] ?? '';
      if (auth.startsWith('Bearer ')) await store.revokeToken(auth.substring(7));
      return Response.ok(
        json.encode({'ok': true}),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'set-cookie': sessionCookie('', clear: true),
        },
      );
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

    // ── 網頁版（Flutter build web）的訂閱 ─────────────────────
    // 網頁版是直接用論壇帳號登入的（透過 /gm 轉發），瀏覽器手上已經有
    // 論壇的 cookie。**不要再要求它登入我們一次**——那等於同一個人登入兩遍。
    // 這裡拿請求上的 cookie 去問論壇「你是誰」，認得出來就建帳號、綁訂閱。
    ..post('/api/web-subscribe', (Request r) async {
      final cookie = r.headers['cookie'] ?? '';
      if (cookie.isEmpty) return bad('沒有論壇登入狀態，請先登入論壇', 401);
      try {
        final target = await apiForRawCookies(cookie);
        final index = await asAccount(target, api.fetchIndex);
        if (!index.user.loggedIn || index.user.name.isEmpty) {
          return bad('論壇顯示未登入，請先在 App 裡登入', 401);
        }
        final account = await store.upsert(
          username: index.user.name,
          cookiePlain: await dumpCookies(target),
        );
        await store.addSubscription(
            account, PushSubscription.fromJson(await bodyOf(r)));
        stdout.writeln('網頁版綁定裝置：${index.user.name}');
        return ok(stateOf(account));
      } on FormatException catch (e) {
        return bad(e.message);
      } catch (e) {
        return bad('$e', 502);
      }
    })

    // ── 論壇內容 ─────────────────────────────────────────────
    // 全部都要登入：論壇本身大部分內容對訪客就是關的，
    // 而且我們手上只有登入後的 cookie 可用。
    ..get('/api/index', (Request r) => forum(r, (t) async =>
        indexJson(await asAccount(t, api.fetchIndex))))
    ..get('/api/forum/<fid|[0-9]+>', (Request r, String fid) => forum(r, (t) async =>
        forumJson(await asAccount(t, () => api.fetchForum(
              int.parse(fid),
              page: intParam(r, 'page', 1),
              query: ForumQuery(
                typeid: intParam(r, 'typeid', 0),
                tab: r.url.queryParameters['tab'] ?? '',
                orderby: r.url.queryParameters['orderby'] ?? '',
                special: r.url.queryParameters['special'] ?? '',
                dateline: intParam(r, 'dateline', 0),
              ),
            )))))
    ..get('/api/thread/<tid|[0-9]+>', (Request r, String tid) => forum(r, (t) async =>
        threadJson(await asAccount(t, () => api.fetchThread(
              int.parse(tid),
              page: intParam(r, 'page', 1),
            )))))
    ..get('/api/pm', (Request r) => forum(r, (t) async {
          final res = await asAccount(t, api.fetchPmList);
          return {
            'items': [for (final p in res.items) pmItemJson(p)],
            'message': res.message,
          };
        }))
    ..get('/api/pm/<touid|[0-9]+>', (Request r, String touid) => forum(r, (t) async =>
        pmChatJson(await asAccount(t, () => api.fetchPmChat(int.parse(touid))))))
    // 注意：開提醒頁**會把那一類標成已讀**，所以只有使用者真的點進來時
    // 才呼叫。背景輪詢一律走頁首的紅點，絕對不能用這支。
    ..get('/api/notice', (Request r) => forum(r, (t) async {
          final res = await asAccount(t, () => api.fetchNotice(
                view: r.url.queryParameters['view'] ?? 'mypost',
                type: r.url.queryParameters['type'] ?? '',
              ));
          return {
            'items': [for (final n in res.items) noticeItemJson(n)],
            'message': res.message,
          };
        }))
    ..get('/api/sign', (Request r) => forum(r, (t) async {
          final res = await asAccount(t, api.fetchSignPage);
          return {
            'signed': res.signed,
            'level': res.level,
            'stats': [
              for (final st in res.stats)
                {'label': st.label, 'value': st.value}
            ],
          };
        }))

    // ── 論壇動作 ─────────────────────────────────────────────
    ..post('/api/reply', (Request r) => forum(r, (t) async {
          final b = await bodyOf(r);
          final res = await asAccount(t, () => api.replyThread(
                fid: b['fid'] as int? ?? 0,
                tid: b['tid'] as int? ?? 0,
                message: b['message'] as String? ?? '',
                repquote: b['repquote'] as String? ?? '',
              ));
          return {'ok': res.ok, 'message': res.message};
        }))
    ..post('/api/pm/<touid|[0-9]+>', (Request r, String touid) => forum(r, (t) async {
          final b = await bodyOf(r);
          final res = await asAccount(t, () => api.sendPm(
                int.parse(touid),
                b['message'] as String? ?? '',
                pmid: b['pmid'] as String? ?? '',
              ));
          return {'ok': res.ok, 'message': res.message};
        }))
    ..post('/api/sign/do', (Request r) => forum(r, (t) async {
          final res = await asAccount(t, api.doSign);
          return {'ok': res.ok, 'message': res.message};
        }))

    // ── 網頁版的跨子網域資源代理 ──────────────────────────────
    // 論壇的圖片有不少放在 img.gamemale.com。那是另一個網域，
    // 瀏覽器抓不到（沒有 CORS），所以由這裡代抓。
    // 不需要登入——這些是公開的圖片資源，而且網頁版的人本來就在瀏覽論壇。
    ..get('/gmimg', (Request r) async {
      final raw = r.url.queryParameters['u'] ?? '';
      final uri = Uri.tryParse(raw);
      // 只准代理論壇自己的網域，否則就變成別人的開放代理
      if (uri == null ||
          !(uri.host == 'gamemale.com' || uri.host.endsWith('.gamemale.com'))) {
        return bad('只能代理論壇的資源');
      }
      try {
        final res = await assetClient.get(uri, headers: {
          'User-Agent': Api.userAgent,
          'Referer': '$kForumOrigin/',
        });
        if (res.statusCode >= 400) return Response.notFound('');
        return Response.ok(res.bodyBytes, headers: {
          'content-type': res.headers['content-type'] ?? 'application/octet-stream',
          'cache-control': 'public, max-age=604800',
        });
      } catch (_) {
        return Response.notFound('');
      }
    })

    // ── 圖片代理 ─────────────────────────────────────────────
    // 論壇的圖片（頭像、附件）要帶登入 cookie 才拿得到，瀏覽器沒有
    // 那份 cookie 也不該有，所以由這裡代抓。
    ..get('/api/img', (Request r) async {
      final a = whoIs(r);
      if (a == null) return bad('尚未登入', 401);
      final raw = r.url.queryParameters['u'] ?? '';
      final uri = Uri.tryParse(raw);
      // 只准代理論壇自己的圖，不要變成別人的開放代理
      if (uri == null || !uri.host.endsWith('gamemale.com')) {
        return bad('只能代理論壇的圖片');
      }
      try {
        final target = await a.connect(store);
        final bytes =
            await asAccount(target, () => Api.instance.getAbsoluteBytes(raw));
        return Response.ok(bytes, headers: {
          'content-type': _guessImageType(bytes, raw),
          // 圖片內容不會變，讓瀏覽器自己快取，不要每次捲動都回來要一遍
          'cache-control': 'private, max-age=86400',
        });
      } catch (e) {
        return Response.notFound('');
      }
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

  // 論壇轉發：讓瀏覽器裡的 Flutter 網頁版能打到論壇（它自己不准跨網域）
  final proxy = ForumProxy();
  Handler withProxy(Handler inner) => (Request r) {
        if (r.url.path == 'gm' || r.url.path.startsWith('gm/')) {
          return proxy.handle(r.change(path: 'gm'));
        }
        return inner(r);
      };

  // Flutter 網頁版在的話就由它當門面（它跟手寫版都要 index.html 與
  // manifest.json，不能同時掛在根路徑）。手寫版是第一階段的原型，
  // 只有在還沒 build web 時才頂上。
  final hasApp = Directory(appRoot).existsSync();
  final site = createStaticHandler(hasApp ? appRoot : webRoot,
      defaultDocument: 'index.html', useHeaderBytesForContentType: true);

  final handler =
      withProxy(Cascade().add(router.call).add(site).handler);

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
  stdout.writeln(hasApp
      ? 'Flutter 網頁版：已掛載（$appRoot）'
      : 'Flutter 網頁版：找不到 $appRoot，改用手寫的通知頁');
}


/// 論壇的圖片網址常常不帶副檔名（attachment.php?aid=…），
/// 靠開頭幾個位元組認格式，認不出來就交給瀏覽器自己嗅。
String _guessImageType(List<int> b, String url) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 7 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
  if (b.length > 5 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
  final lower = url.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}
