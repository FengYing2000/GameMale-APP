import 'dart:async';
import 'dart:io';

import 'accounts.dart';
import 'forum.dart';
import 'push_client.dart';

/// 一則要送出去的通知。抽出來是為了讓輪詢邏輯能離線測試——
/// 真的去敲論壇、真的送推播的部分都在外面。
class Outgoing {
  const Outgoing(this.title, this.body, {this.tag = 'gm'});

  final String title;
  final String body;

  /// 同一個 tag 的通知在手機上會互相取代，不會疊成一排。
  final String tag;

  Map<String, dynamic> toPayload() =>
      {'title': title, 'body': body, 'tag': tag, 'url': '/'};

  @override
  String toString() => '[$tag] $title / $body';
}

/// 對單一帳號跑一輪，算出「這次該推什麼」。
///
/// 這個函式**不碰網路也不寫檔**：外面把論壇查到的結果餵進來，它只決定要不要
/// 通知，並且就地更新帳號上的計數與日期。這樣所有的判斷條件都能離線測到，
/// 不用真的等一天或真的收一則私訊。
List<Outgoing> decideNotifications({
  required Account account,
  required PollSnapshot snapshot,
  required String today,
  required String nowHhmm,
  SubmitOutcome? signResult,
}) {
  final out = <Outgoing>[];

  // 連不上就什麼都不判斷，直接等下一輪
  if (!snapshot.reachable) return out;

  // ── 登入過期 ────────────────────────────────────────────────
  if (!snapshot.loggedIn) {
    // 只在「剛變成過期」時推一次，不要每輪都吵
    if (account.cookieStatus != 'expired') {
      account.cookieStatus = 'expired';
      out.add(const Outgoing(
        '[帳號] 登入憑證已失效',
        '論壇登入狀態已過期，請重新登入以繼續接收通知',
        tag: 'auth',
      ));
    }
    // 過期之後就別再判斷未讀了，那些數字都是零，
    // 不然使用者讀完重新登入時會被當成「變多」而重複通知
    return out;
  }
  account.cookieStatus = 'ok';

  // ── 新提醒／新私訊 ──────────────────────────────────────────
  // 只有「變多」才通知：讀掉變少不吵、沒變也不重複吵。
  if (account.notifyNotice && snapshot.notice > account.lastNotice) {
    out.add(Outgoing(
      '[論壇提醒]',
      '您有 ${snapshot.notice} 則未讀提醒',
      tag: 'notice',
    ));
  }
  if (account.notifyPm && snapshot.pm > account.lastPm) {
    // 直接把訊息本身放進通知：標題是寄件者，內文是訊息預覽。
    // 抓不到內容時退回未讀則數。
    // 標題＝［分類］寄件者，內文＝訊息本身。iOS 會自己在標題底下補上
    // 「from GameMale」，所以標題不用再放 App 名字。
    final hasContent = snapshot.latestPmName.isNotEmpty;
    out.add(Outgoing(
      hasContent ? '[私人消息] ${snapshot.latestPmName}' : '[私人消息]',
      hasContent && snapshot.latestPmPreview.isNotEmpty
          ? snapshot.latestPmPreview
          : '您有 ${snapshot.pm} 則未讀消息',
      tag: 'pm',
    ));
  }
  account.lastNotice = snapshot.notice;
  account.lastPm = snapshot.pm;

  // ── 簽到 ────────────────────────────────────────────────────
  // 以論壇的實際狀態為準。只看 lastSignDate 的話，使用者自己在 App 或
  // 論壇網頁上簽的我們不知道，就會一直推「尚未簽到」。
  // 論壇問不到（null）時才退回自己的紀錄。
  final signedToday =
      snapshot.signedOnForum ?? (account.lastSignDate == today);
  // 論壇說已經簽了，就把紀錄補上，之後不用每輪都再問一次也判斷得出來
  if (snapshot.signedOnForum == true) account.lastSignDate = today;
  if (account.autoSign) {
    // 有開自動簽到：伺服器代簽，推結果
    if (signResult != null) {
      account.lastSignDate = signResult.ok ? today : account.lastSignDate;
      out.add(Outgoing(
        signResult.ok ? '[每日簽到] 已完成' : '[每日簽到] 失敗',
        signResult.message,
        tag: 'sign',
      ));
    }
  } else if (!signedToday &&
      account.lastRemindDate != today &&
      nowHhmm.compareTo(account.signReminderAt) >= 0) {
    // 沒開自動簽到：過了設定的時間就提醒一次。
    //
    // 這裡**不能寫成 nowHhmm == signReminderAt**：輪詢是每幾分鐘一次，
    // 設 09:00 而輪詢落在 08:58 與 09:03，那一整天就永遠不會提醒。
    // 改成「過了就提醒」，再用 lastRemindDate 保證一天只推一則。
    // HH:mm 補零過，字串比大小等於時間比大小。
    account.lastRemindDate = today;
    out.add(const Outgoing('[每日簽到]', '您今日尚未完成簽到', tag: 'sign'));
  }

  return out;
}

/// 簽到結果。用自己的型別而不是直接吃 gm_api 的 SubmitResult，
/// 這樣上面那個純邏輯函式不用連 gm_api 一起拉進測試。
class SubmitOutcome {
  const SubmitOutcome(this.ok, this.message);
  final bool ok;
  final String message;
}

/// 需不需要在這一輪替他簽到
bool shouldSign(Account account, String today) =>
    account.autoSign && account.lastSignDate != today;

/// 排程輪詢。
class Poller {
  Poller({
    required this.store,
    required this.push,
    this.interval = const Duration(minutes: 5),
  });

  final AccountStore store;
  final PushClient push;
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
    // 啟動後先跑一次，不要等第一個間隔到
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 跑一輪。上一輪還沒跑完就跳過——論壇慢的時候不要疊在一起打。
  Future<void> tick() async {
    if (_running) {
      stdout.writeln('上一輪還沒結束，這輪跳過');
      return;
    }
    _running = true;
    try {
      for (final account in store.all) {
        try {
          await _pollAccount(account);
          stdout.writeln('輪詢 ${account.username}：'
              '提醒 ${account.lastNotice}／私訊 ${account.lastPm}');
        } catch (e) {
          // 一個帳號出事不該讓其他帳號的通知也停掉
          stdout.writeln('輪詢 ${account.username} 失敗：$e');
        }
      }
      await store.flush();
    } finally {
      _running = false;
    }
  }

  Future<void> _pollAccount(Account account) async {
    // 已知過期就別再拿失效的 cookie 去敲論壇，等使用者重新登入
    if (account.cookieStatus == 'expired') return;

    final target = await account.connect(store);
    final snapshot = await pollOnce(target);
    final today = todayTaipei();

    SubmitOutcome? signResult;
    if (snapshot.reachable && snapshot.loggedIn && shouldSign(account, today)) {
      final r = await signFor(target);
      signResult = SubmitOutcome(r.ok, r.message);
    }

    final messages = decideNotifications(
      account: account,
      snapshot: snapshot,
      today: today,
      nowHhmm: nowHhmmTaipei(),
      signResult: signResult,
    );

    if (snapshot.reachable) {
      account.lastCheckedAt = DateTime.now().toIso8601String();
    }

    for (final m in messages) {
      await _send(account, m);
    }
  }

  Future<void> _send(Account account, Outgoing message) async {
    for (final sub in [...account.subscriptions]) {
      final res = await push.send(subscription: sub, payload: message.toPayload());
      // 成功也要留一筆：不然「使用者說沒收到」時完全查不出是沒送、
      // 送失敗、還是送出去了但手機沒顯示
      if (res.ok) stdout.writeln('已推播給 ${account.username}：$message');
      if (res.outcome == PushOutcome.gone) {
        // 使用者移除了 App 或關掉通知，留著只會每輪都失敗
        await store.removeSubscription(sub.endpoint);
        stdout.writeln('訂閱已失效，移除：${account.username}');
      } else if (!res.ok) {
        stdout.writeln('推播失敗（${account.username}）：$res');
      }
    }
  }
}
