import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/services/browser_fetch.dart';

/// 走 WebView 傳輸時拿不到狀態碼與標頭（`fetch()` 只回文字），所以
/// 「這是不是攔截頁」只能靠內文特徵判斷。判斷錯的後果非常嚴重：
/// 每一頁正常內容都被當成攔截，驗證頁不斷跳出、解了也沒用。
void main() {
  group('認得出真正的攔截頁', () {
    test('攔截頁專屬的設定物件', () {
      expect(
        BrowserFetch.looksLikeChallenge(
          '<html><head><title>Just a moment...</title></head>'
          '<body><script>window._cf_chl_opt={cvId:"3",cType:"managed"};</script>',
        ),
        isTrue,
      );
    });

    test('舊版的驗證標記', () {
      expect(
        BrowserFetch.looksLikeChallenge(
          '<div class="cf-browser-verification cf-im-under-attack">',
        ),
        isTrue,
      );
    });
  });

  group('正常頁面絕對不能被誤判', () {
    test('Cloudflare 注入到正常頁面的偵測腳本不算攔截', () {
      // ⚠️ 這是害整套機制失效的那個 bug。
      // 開啟 JS Detections 之後，Cloudflare 會把這支腳本插進**每一個**
      // 正常頁面。之前拿 'challenge-platform' 當判斷依據，結果每一頁
      // 論壇內容都被當成攔截頁，驗證頁不斷跳出、解了也沒用。
      expect(
        BrowserFetch.looksLikeChallenge(
          '<html><body><div id="mainbox">論壇內容</div>'
          '<script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script>'
          '</body></html>',
        ),
        isFalse,
      );
    });

    test('一般帖子頁', () {
      expect(
        BrowserFetch.looksLikeChallenge(
          '<div id="postlist"><div class="plc">內容</div></div>',
        ),
        isFalse,
      );
    });

    test('帖子內文剛好在討論 Cloudflare 也不算', () {
      expect(
        BrowserFetch.looksLikeChallenge(
          '<div class="plc">我在研究 cloudflare 的 browser verification 怎麼運作</div>',
        ),
        isFalse,
      );
    });

    test('空字串', () {
      expect(BrowserFetch.looksLikeChallenge(''), isFalse);
    });
  });

  group('頁面探測腳本', () {
    test('不能用桌面版的選擇器認論壇', () {
      // 另一個害它永遠判不出 forum 的 bug：#hd／#nv／.bm／#ft 是**桌面版**
      // Discuz 的結構，手機模板一個都沒有（實測樣本裡全是 0）。
      // 手機版頁面裡一定有大量指向 forum.php／home.php 的連結。
      expect(BrowserFetch.probeJs, contains('forum.php'));
      expect(BrowserFetch.probeJs, contains('home.php'));
      expect(
        BrowserFetch.probeJs.contains("'#hd"),
        isFalse,
        reason: '桌面選擇器不該回來',
      );
    });

    test('探測腳本也不能比對 challenge-platform', () {
      expect(
        BrowserFetch.probeJs.contains('challenge-platform'),
        isFalse,
        reason: '那支腳本在正常頁面上也有',
      );
      expect(BrowserFetch.probeJs, contains('_cf_chl_opt'));
    });
  });
}
