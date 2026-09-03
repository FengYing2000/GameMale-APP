import 'package:gm_server/accounts.dart';
import 'package:gm_server/forum.dart';
import 'package:gm_server/poller.dart';
import 'package:test/test.dart';

Account acc({
  bool autoSign = false,
  String signReminderAt = '09:00',
  int lastNotice = 0,
  int lastPm = 0,
  String? lastSignDate,
  String? lastRemindDate,
  String cookieStatus = 'ok',
  int authFailStreak = 0,
  bool notifyNotice = true,
  bool notifyPm = true,
}) =>
    Account(
      id: 'a1',
      username: 'tester',
      cookieSealed: 'x',
      cookieStatus: cookieStatus,
      authFailStreak: authFailStreak,
      autoSign: autoSign,
      signReminderAt: signReminderAt,
      notifyNotice: notifyNotice,
      notifyPm: notifyPm,
      lastNotice: lastNotice,
      lastPm: lastPm,
      lastSignDate: lastSignDate,
      lastRemindDate: lastRemindDate,
    );

PollSnapshot snapPm(int pm, {required String name, required String preview}) =>
    PollSnapshot(
      reachable: true,
      loggedIn: true,
      notice: 0,
      pm: pm,
      latestPmName: name,
      latestPmPreview: preview,
    );

PollSnapshot snap({
  bool reachable = true,
  bool loggedIn = true,
  int notice = 0,
  int pm = 0,
}) =>
    PollSnapshot(
        reachable: reachable, loggedIn: loggedIn, notice: notice, pm: pm);

List<Outgoing> decide(
  Account a,
  PollSnapshot s, {
  String today = '2026-09-01',
  // 預設時間刻意早於簽到提醒時間，這樣測提醒/私訊的案例才不會
  // 順便觸發簽到提醒而看不出真正在驗什麼
  String now = '08:00',
  SubmitOutcome? sign,
}) =>
    decideNotifications(
      account: a,
      snapshot: s,
      today: today,
      nowHhmm: now,
      signResult: sign,
    );

void main() {
  group('提醒與私訊：只有變多才通知', () {
    test('從 0 變 2 要通知', () {
      final a = acc();
      final out = decide(a, snap(notice: 2));
      expect(out.map((o) => o.tag), ['notice']);
      expect(out.first.body, contains('2'));
      expect(a.lastNotice, 2, reason: '基準要跟著更新');
    });

    test('數字沒變不要重複吵', () {
      final a = acc(lastNotice: 3);
      expect(decide(a, snap(notice: 3)), isEmpty);
    });

    test('讀掉變少不要通知', () {
      final a = acc(lastNotice: 5);
      expect(decide(a, snap(notice: 2)), isEmpty);
      expect(a.lastNotice, 2, reason: '基準要往下修，否則之後回到 5 就不會通知了');
    });

    test('讀掉之後又來新的，要再通知一次', () {
      final a = acc(lastNotice: 5);
      decide(a, snap(notice: 0)); // 全部讀完
      final out = decide(a, snap(notice: 1));
      expect(out.map((o) => o.tag), ['notice']);
    });

    test('提醒與私訊同時變多，兩則都要送', () {
      final a = acc();
      expect(decide(a, snap(notice: 1, pm: 2)).map((o) => o.tag),
          ['notice', 'pm']);
    });

    test('關掉的類別不送', () {
      final a = acc(notifyNotice: false);
      expect(decide(a, snap(notice: 9, pm: 1)).map((o) => o.tag), ['pm']);
      expect(a.lastNotice, 9, reason: '不通知但基準仍要更新，免得之後打開就被舊帳灌爆');
    });

    test('提醒通知講得出未讀總數', () {
      final a = acc(lastNotice: 2);
      expect(decide(a, snap(notice: 5)).first.body, contains('5'));
    });

    test('私訊通知直接顯示寄件者與內容', () {
      final a = acc();
      final out = decide(a, snapPm(2, name: 'YanShen', preview: '測試訊息'));
      expect(out.single.title, '[私人消息] YanShen');
      expect(out.single.body, '測試訊息');
    });
  });

  group('連不上論壇', () {
    test('什麼都不做，也不要動基準', () {
      final a = acc(lastNotice: 4, cookieStatus: 'ok');
      expect(decide(a, snap(reachable: false)), isEmpty);
      expect(a.lastNotice, 4);
      expect(a.cookieStatus, 'ok', reason: '網路抖一下不能被當成登出');
    });
  });

  group('登入過期', () {
    test('第一輪不推，連兩輪才算真的過期', () {
      // 實機上被這個咬過：半夜推了「登入憑證已失效」，而使用者的登入
      // 好好的。單獨一次判定不作數，晚五分鐘知道遠比誤推好。
      final a = acc();
      expect(decide(a, snap(loggedIn: false)), isEmpty,
          reason: '第一輪只記次數，不推播');
      expect(a.cookieStatus, 'ok', reason: '還沒確定就別改狀態');

      final out = decide(a, snap(loggedIn: false));
      expect(out.map((o) => o.tag), ['auth']);
      expect(a.cookieStatus, 'expired');
    });

    test('中間只要成功一次就重新計數', () {
      final a = acc();
      decide(a, snap(loggedIn: false)); // 第 1 次
      decide(a, snap(notice: 0)); // 登入正常
      expect(a.authFailStreak, 0, reason: '成功一次就要歸零');
      expect(decide(a, snap(loggedIn: false)), isEmpty,
          reason: '重新從第 1 次算起，不能接著上次的數字直接推');
    });

    test('已經是過期狀態就不要每輪都吵', () {
      final a = acc(cookieStatus: 'expired', authFailStreak: 5);
      expect(decide(a, snap(loggedIn: false)), isEmpty);
    });

    test('過期時不要順便判斷未讀', () {
      // 沒登入時未讀數都是 0，若照樣寫進基準，等他重新登入
      // 就會把原有的未讀當成「全部都是新的」再吵一次
      final a = acc(lastNotice: 7, lastPm: 3, authFailStreak: 1);
      decide(a, snap(loggedIn: false));
      expect(a.lastNotice, 7);
      expect(a.lastPm, 3);
    });

    test('重新登入後恢復正常，不會把舊的未讀當成新的', () {
      final a = acc(lastNotice: 7, cookieStatus: 'expired');
      final out = decide(a, snap(notice: 7));
      expect(out, isEmpty);
      expect(a.cookieStatus, 'ok');
      expect(a.authFailStreak, 0);
    });

    test('連不上時完全不碰登入狀態', () {
      // 判讀不出來的頁面在 pollOnce 就會回 reachable:false，
      // 走到這裡等於「這輪什麼都不知道」，不能累積過期次數
      final a = acc();
      expect(decide(a, snap(reachable: false, loggedIn: false)), isEmpty);
      expect(a.authFailStreak, 0);
      expect(a.cookieStatus, 'ok');
    });
  });

  group('簽到：沒開自動簽到就只提醒', () {
    test('時間到了推提醒', () {
      final a = acc(signReminderAt: '09:00');
      expect(decide(a, snap(), now: '09:00').map((o) => o.tag), ['sign']);
    });

    test('時間沒到不推', () {
      final a = acc(signReminderAt: '09:00');
      expect(decide(a, snap(), now: '08:59'), isEmpty);
    });

    test('輪詢沒剛好落在那一分鐘也要推得到', () {
      // 輪詢是每幾分鐘一次，設 09:00 而 tick 落在 09:03 是常態。
      // 寫成 == 判斷的話這一整天就永遠不會提醒。
      final a = acc(signReminderAt: '09:00');
      expect(decide(a, snap(), now: '09:03').map((o) => o.tag), ['sign']);
    });

    test('晚上才第一次輪詢，當天仍補得到提醒', () {
      final a = acc(signReminderAt: '09:00');
      expect(decide(a, snap(), now: '23:30').map((o) => o.tag), ['sign']);
    });

    test('同一分鐘被輪詢兩次也只推一則', () {
      final a = acc(signReminderAt: '09:00');
      expect(decide(a, snap(), now: '09:00'), hasLength(1));
      expect(decide(a, snap(), now: '09:00'), isEmpty);
    });

    test('使用者自己在論壇簽的也算——不能只看伺服器的紀錄', () {
      // 這是實際踩到的 bug：lastSignDate 只記錄伺服器代簽的結果，
      // 使用者自己簽的我們不知道，於是一直推「尚未簽到」
      final a = acc(signReminderAt: '09:00');
      final s = PollSnapshot(
        reachable: true, loggedIn: true, notice: 0, pm: 0,
        signedOnForum: true,
      );
      expect(decideNotifications(
        account: a, snapshot: s, today: '2026-09-01', nowHhmm: '09:00',
      ), isEmpty);
      expect(a.lastSignDate, '2026-09-01', reason: '順便把紀錄補上');
    });

    test('論壇問不到簽到狀態時，沿用自己的紀錄', () {
      final a = acc(signReminderAt: '09:00', lastSignDate: '2026-09-01');
      final s = PollSnapshot(
        reachable: true, loggedIn: true, notice: 0, pm: 0,
        signedOnForum: null,
      );
      expect(decideNotifications(
        account: a, snapshot: s, today: '2026-09-01', nowHhmm: '09:00',
      ), isEmpty);
    });

    test('今天已經簽過就不要再提醒', () {
      final a = acc(signReminderAt: '09:00', lastSignDate: '2026-09-01');
      expect(decide(a, snap(), now: '09:00'), isEmpty);
    });

    test('隔天會再提醒一次', () {
      final a = acc(signReminderAt: '09:00');
      decide(a, snap(), today: '2026-09-01', now: '09:00');
      final out = decide(a, snap(), today: '2026-09-02', now: '09:00');
      expect(out.map((o) => o.tag), ['sign']);
    });

    test('沒開自動簽到就不該有簽到結果', () {
      final a = acc(autoSign: false);
      // 就算外面誤傳了結果進來也不要推——那代表呼叫端有 bug，
      // 但使用者不該因此收到他沒要求的通知
      final out = decide(a, snap(), sign: const SubmitOutcome(true, '簽到成功'));
      expect(out.where((o) => o.title.contains('簽到完成')), isEmpty);
    });
  });

  group('簽到：有開自動簽到就代簽並推結果', () {
    test('成功要推，並記下日期', () {
      final a = acc(autoSign: true);
      final out = decide(a, snap(), sign: const SubmitOutcome(true, '簽到成功，獲得 5 金幣'));
      expect(out.single.title, '[每日簽到] 已完成');
      expect(out.single.body, contains('5 金幣'));
      expect(a.lastSignDate, '2026-09-01');
    });

    test('失敗也要讓使用者知道，但不要記成已簽', () {
      final a = acc(autoSign: true);
      final out = decide(a, snap(), sign: const SubmitOutcome(false, '需要先登入才能簽到'));
      expect(out.single.title, '[每日簽到] 失敗');
      expect(a.lastSignDate, isNull, reason: '沒簽成功就不能記成今天簽過了');
    });
  });

  group('要不要替他簽到', () {
    test('沒開就不簽', () {
      expect(shouldSign(acc(autoSign: false), '2026-09-01'), isFalse);
    });

    test('開了而且今天還沒簽就簽', () {
      expect(shouldSign(acc(autoSign: true), '2026-09-01'), isTrue);
    });

    test('今天簽過就不要再簽', () {
      expect(
        shouldSign(acc(autoSign: true, lastSignDate: '2026-09-01'), '2026-09-01'),
        isFalse,
      );
    });

    test('隔天要再簽', () {
      expect(
        shouldSign(acc(autoSign: true, lastSignDate: '2026-08-31'), '2026-09-01'),
        isTrue,
      );
    });
  });

  group('台北時間', () {
    test('UTC 換算成台北的日期', () {
      // UTC 2026-09-01 16:30 = 台北 2026-09-02 00:30，日期要跨過去
      expect(todayTaipei(DateTime.utc(2026, 9, 1, 16, 30)), '2026-09-02');
      expect(todayTaipei(DateTime.utc(2026, 9, 1, 15, 30)), '2026-09-01');
    });

    test('HH:mm 也要是台北時間', () {
      expect(nowHhmmTaipei(DateTime.utc(2026, 9, 1, 1, 5)), '09:05');
      expect(nowHhmmTaipei(DateTime.utc(2026, 9, 1, 16, 0)), '00:00');
    });
  });
}
