import 'package:gm_api/http.dart';
import 'package:test/test.dart';

/// isChallengeHtml 不能只憑內容出現關鍵字就判成攔截頁。
/// CODE. 板塊有討論 CF 驗證的技術帖，正常板塊頁內容裡就帶了
/// dev8133_cloudflare / turnstile / 请稍候 這些字，整頁被誤判成挑戰、
/// 跳「需要驗證」。要看攔截頁的結構（title 请稍候、頁面很小）。
void main() {
  group('isChallengeHtml', () {
    test('正常板塊頁（大、title 是板塊名）內容含 CF 關鍵字不算挑戰', () {
      final body = '${'讨论 dev8133_cloudflare 的 '
          'challenges.cloudflare.com/turnstile，卡在"请稍候" ' * 50}'
          '${'x' * 30000}';
      final html =
          '<html><head><title>C O D E. - GameMale</title></head><body>$body</body></html>';
      expect(html.length, greaterThan(20000));
      expect(isChallengeHtml(html), isFalse);
    });

    test('真攔截頁（title 请稍候、只有幾 KB）算挑戰', () {
      const html = '<html><head><title>请稍候...</title></head><body>'
          '<script src="https://challenges.cloudflare.com/turnstile/v0/api.js">'
          '</script></body></html>';
      expect(isChallengeHtml(html), isTrue);
    });

    test('小的攔截片段帶 CF 標記也算', () {
      const html = '<html><head></head><body>'
          '<div id="cf-browser-verification"></div></body></html>';
      expect(isChallengeHtml(html), isTrue);
    });
  });
}
