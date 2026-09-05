import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/services/browser_fetch.dart';

/// 走 WebView 傳輸時拿不到狀態碼與標頭（`fetch()` 只回文字），
/// 所以「這是不是挑戰頁」只能靠內文特徵判斷。判斷錯的話，使用者會拿到
/// 一片空白的頁面而不是「請通過驗證」的提示。
void main() {
  group('認得出 WebView 拿回來的挑戰頁', () {
    test('挑戰頁的腳本路徑', () {
      expect(
        BrowserFetch.looksLikeChallenge(
            '<html><head><script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>'),
        isTrue,
      );
    });

    test('舊版的驗證標記', () {
      expect(
        BrowserFetch.looksLikeChallenge(
            '<div class="cf-browser-verification cf-im-under-attack">'),
        isTrue,
      );
    });

    test('挑戰設定物件', () {
      expect(
        BrowserFetch.looksLikeChallenge('window._cf_chl_opt={cvId:"3"}'),
        isTrue,
      );
    });
  });

  group('正常的論壇頁面不能被誤判', () {
    test('一般帖子頁', () {
      expect(
        BrowserFetch.looksLikeChallenge(
            '<div id="postlist"><div class="plc">內容</div></div>'),
        isFalse,
      );
    });

    test('帖子內文剛好提到那些字也不算', () {
      // 這是個講 Cloudflare 的技術帖，不是挑戰頁
      expect(
        BrowserFetch.looksLikeChallenge(
            '<div class="plc">我在研究 cloudflare 的 browser verification 怎麼運作</div>'),
        isFalse,
      );
    });

    test('空字串', () {
      expect(BrowserFetch.looksLikeChallenge(''), isFalse);
    });
  });
}
