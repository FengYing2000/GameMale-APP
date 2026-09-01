import 'package:cookie_jar/cookie_jar.dart';
import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import 'package:test/test.dart';

/// 伺服器要同時替好幾個帳號輪詢，每個帳號的 cookie 與 formhash 都必須分開。
/// formhash 原本是模組層的全域變數，共用會讓 A 帳號的 hash 被送進 B 帳號的
/// 請求——論壇會回「請重新登入」，而且那種錯很難查。這裡守住這條線。
void main() {
  group('多帳號互不干擾', () {
    late Api a;
    late Api b;

    setUp(() async {
      a = await Api.forAccount(CookieJar());
      b = await Api.forAccount(CookieJar());
    });

    test('兩條連線是不同物件', () => expect(identical(a, b), isFalse));

    test('formhash 各自獨立', () async {
      await Api.runAs(a, () async => a.formhash = 'hash-A');
      await Api.runAs(b, () async => b.formhash = 'hash-B');

      expect(await Api.runAs(a, () async => api.formhash), 'hash-A');
      expect(await Api.runAs(b, () async => api.formhash), 'hash-B');
    });

    test('模組層的 formhash 讀到的是當下 Zone 那條連線的', () async {
      a.formhash = 'AAA';
      b.formhash = 'BBB';
      expect(await Api.runAs(a, () async => api.formhash), 'AAA');
      expect(await Api.runAs(b, () async => api.formhash), 'BBB');
    });

    test('跨 await 之後還在同一條連線上', () async {
      a.formhash = 'still-A';
      final got = await Api.runAs(a, () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return api.formhash;
      });
      expect(got, 'still-A', reason: 'Zone 要能跟著非同步接續走');
    });

    test('巢狀 runAs 以內層為準，離開後回到外層', () async {
      a.formhash = 'outer';
      b.formhash = 'inner';
      final seen = <String?>[];
      await Api.runAs(a, () async {
        seen.add(api.formhash);
        await Api.runAs(b, () async => seen.add(api.formhash));
        seen.add(api.formhash);
      });
      expect(seen, ['outer', 'inner', 'outer']);
    });

    test('Zone 外面拿到的是預設連線，不是誰的帳號', () async {
      a.formhash = 'account-A';
      await Api.runAs(a, () async => null);
      // App 端從來不設 Zone，行為必須跟以前完全一樣
      expect(api.formhash, isNot('account-A'));
    });
  });
}
