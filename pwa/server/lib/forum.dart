import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import 'package:gm_api/parse.dart' as parse;
import 'package:gm_api/s2t.dart';

import 'accounts.dart';

/// 把伺服器這邊的東西接到純 Dart 的 `gm_api` 上。
///
/// 跟 Flutter App 的 `lib/platform_bindings.dart` 是對稱的：同一套解析，
/// 兩邊各自注入自己的 cookie 儲存與轉換表來源。
///
/// **要在任何 Api 呼叫之前先跑一次。**
Future<void> installServerBindings({String assetDir = '/srv/assets'}) async {
  // 伺服器不用預設那條連線存 cookie——每個帳號都會有自己的一條，
  // 走 Api.forAccount。預設這條只拿來做登入前的探路。
  Api.cookieJarFactory = CookieJar.new;

  S2T.assetLoader = (path) async {
    // gm_api 傳進來的是 Flutter 的資產路徑（assets/s2t.json），
    // 這裡只取檔名，對到伺服器自己的資料夾
    final name = path.split('/').last;
    return File('$assetDir/$name').readAsString(encoding: utf8);
  };

  await Api.instance.init();

  try {
    await S2T.instance.load();
  } catch (_) {
    // 轉換表讀不到就原樣輸出。通知會是簡體而不是繁體，
    // 但不該讓整個服務起不來。
  }
}

// ── cookie 的序列化 ────────────────────────────────────────────────
// 存進資料檔前會再過一次 AES-256-GCM（見 SecretBox），這裡只負責
// 把 CookieJar 的內容變成字串、以及變回來。

String encodeCookies(List<Cookie> cookies) => json.encode([
      for (final c in cookies)
        {
          'name': c.name,
          'value': c.value,
          'domain': c.domain,
          'path': c.path,
          'expires': c.expires?.toIso8601String(),
          'httpOnly': c.httpOnly,
          'secure': c.secure,
        }
    ]);

List<Cookie> decodeCookies(String raw) {
  final out = <Cookie>[];
  for (final e in json.decode(raw) as List) {
    final m = (e as Map).cast<String, dynamic>();
    final c = Cookie(m['name'] as String, m['value'] as String)
      ..domain = m['domain'] as String?
      ..path = m['path'] as String?
      ..httpOnly = m['httpOnly'] as bool? ?? false
      ..secure = m['secure'] as bool? ?? false;
    final exp = m['expires'] as String?;
    if (exp != null) c.expires = DateTime.tryParse(exp);
    out.add(c);
  }
  return out;
}

Future<String> dumpCookies(Api target) async =>
    encodeCookies(await target.cookiesFor(Uri.parse(kOrigin)));

/// 用瀏覽器送上來的 Cookie 標頭開一條連線。
///
/// 網頁版的使用者是直接登入論壇的（走 /gm 轉發），那些 cookie 就在
/// 請求標頭上，拿來當 session 用即可，不必再登入一次。
Future<Api> apiForRawCookies(String header) async {
  final jar = CookieJar();
  final cookies = <Cookie>[];
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final name = part.substring(0, i).trim();
    // 我們自己的 session cookie 不要送去論壇
    if (name == 'gm_session') continue;
    cookies.add(Cookie(name, part.substring(i + 1).trim()));
  }
  await jar.saveFromResponse(Uri.parse(kForumOrigin), cookies);
  return Api.forAccount(jar);
}

/// 用某個帳號存下來的 cookie 開一條連線
Future<Api> apiForCookie(String cookiePlain) async {
  final jar = CookieJar();
  await jar.saveFromResponse(Uri.parse(kOrigin), decodeCookies(cookiePlain));
  return Api.forAccount(jar);
}

// ── 登入 ──────────────────────────────────────────────────────────

/// 登入是兩步的：先取表單（拿 loginhash 與驗證碼），使用者填完再送出。
/// 這兩步必須是**同一條連線**——loginhash 跟 cookie 是綁在一起的，
/// 中間換一條就會一直失敗。所以把待完成的登入暫存起來。
class PendingLogin {
  PendingLogin(this.api, this.meta) : startedAt = DateTime.now();

  final Api api;
  final LoginMeta meta;
  final DateTime startedAt;

  bool get expired =>
      DateTime.now().difference(startedAt) > const Duration(minutes: 10);
}

class LoginSessions {
  final Map<String, PendingLogin> _pending = {};

  /// 開始一次登入，回傳暫存 id 與表單需要的資訊
  Future<({String id, LoginMeta meta})> begin() async {
    _sweep();
    final target = await Api.forAccount(CookieJar());
    final meta = await Api.runAs(target, api.loginMeta);
    final id = _randomId();
    _pending[id] = PendingLogin(target, meta);
    return (id: id, meta: meta);
  }

  PendingLogin? take(String id) {
    _sweep();
    return _pending.remove(id);
  }

  /// 沒完成的登入不要一直佔記憶體
  void _sweep() => _pending.removeWhere((_, p) => p.expired);

  int get pendingCount => _pending.length;
}

/// 針對某個帳號執行一次論壇動作。
///
/// 一定要包在 [Api.runAs] 裡，否則會跑到預設那條連線上——那條沒有登入，
/// 而且多帳號時會互相踩到。
Future<T> asAccount<T>(Api target, Future<T> Function() body) =>
    Api.runAs(target, body);

// ── 輪詢要用的動作 ────────────────────────────────────────────────

/// 一次輪詢的結果。
class PollSnapshot {
  const PollSnapshot({
    required this.reachable,
    required this.loggedIn,
    required this.notice,
    required this.pm,
    this.latestPmName = '',
    this.latestPmPreview = '',
  });

  /// 論壇連得到嗎。連不到就什麼都不要判斷——網路抖一下不該被當成登出。
  final bool reachable;
  final bool loggedIn;
  final int notice;
  final int pm;

  /// 最新一則未讀私訊的寄件者與內容，讓通知能直接顯示訊息本身
  /// 而不只是「你有 N 則未讀」。沒有未讀時為空字串。
  final String latestPmName;
  final String latestPmPreview;
}

/// 查一次未讀數，順便判斷還在不在登入狀態。
///
/// **提醒**用頁首的提醒選單，不要用 fetchNotice——後者會把提醒標成已讀，
/// 等於一邊查一邊把使用者的紅點清掉。
///
/// **私訊要另外抓對話列表**，不能用頁首那個數字。頁首的私訊數是一個
/// 「新訊息提示」，使用者只要瞄一眼訊息列表，論壇就把它清成 0——可是
/// 對話本身還是未讀的。只看頁首的話，實際有好幾則沒讀卻永遠推不出通知。
/// 每則對話自己的未讀數才是真的，跟 App 裡紅點用的是同一個來源。
Future<PollSnapshot> pollOnce(Api target) => asAccount(target, () async {
      final bool loggedIn;
      final int notice;
      var pm = 0;
      try {
        final doc =
            parse.toDoc(await Api.instance.get('forum.php', desktop: true));
        final b = api.parsePromptCounts(doc);
        loggedIn = parse.isLoggedIn(doc);
        notice = b.notice;
        pm = b.pm;
      } catch (_) {
        // 連不上不代表登出。這種時候什麼都不做，下一輪再試，
        // 免得網路抖一下就把使用者標成過期、逼他重新登入。
        return const PollSnapshot(
            reachable: false, loggedIn: true, notice: 0, pm: 0);
      }

      var latestName = '';
      var latestPreview = '';
      if (loggedIn) {
        try {
          final list = await api.fetchPmList();
          pm = list.items.fold(0, (sum, i) => sum + i.unread);
          // 列表本來就依時間排序，第一則未讀的就是最新那則
          for (final it in list.items) {
            if (it.unread > 0) {
              latestName = it.name;
              latestPreview = it.last;
              break;
            }
          }
        } catch (_) {
          // 對話列表抓不到就退回頁首那個數字，至少不會完全沒有通知
        }
      }

      return PollSnapshot(
        reachable: true,
        loggedIn: loggedIn,
        notice: notice,
        pm: pm,
        latestPmName: latestName,
        latestPmPreview: latestPreview,
      );
    });

Future<SubmitResult> signFor(Api target) => asAccount(target, api.doSign);

/// 台北時間的今天（yyyy-MM-dd）。容器的 TZ 設成 Asia/Taipei，
/// 但這裡不依賴那個設定，自己算，免得哪天環境變了就靜靜地錯一天。
String todayTaipei([DateTime? now]) {
  final t = (now ?? DateTime.now().toUtc()).add(const Duration(hours: 8));
  return '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

/// 台北時間現在的 HH:mm
String nowHhmmTaipei([DateTime? now]) {
  final t = (now ?? DateTime.now().toUtc()).add(const Duration(hours: 8));
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

String _randomId([int bytes = 16]) {
  final r = math.Random.secure();
  return List<int>.generate(bytes, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// 讓 [Account] 直接開連線
extension AccountApi on Account {
  Future<Api> connect(AccountStore store) =>
      apiForCookie(store.openCookie(this));
}
