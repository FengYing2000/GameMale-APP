import 'package:gm_api/http.dart';
import 'package:test/test.dart';

/// 網頁版把 kOrigin 指到自家的轉發位址，但頁面內容是論壇原樣吐回來的，
/// 裡面的連結一律是論壇本尊的網址。凡是「這是不是站內連結」的判斷都要
/// 兩種都認，否則網頁版會把站內連結當成站外而不處理。
void main() {
  group('代理模式下的站內網址判斷', () {
    tearDown(() {
      kOrigin = kForumOrigin;
      kAssetProxyPrefix = '';
    });

    test('原生版：kOrigin 就是論壇本尊', () {
      expect(kOrigin, kForumOrigin);
    });

    test('網頁版：其他子網域的圖片走圖片代理', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      final out = absolute('https://img.gamemale.com/a/b.png');
      expect(out, startsWith('https://example.test/gmimg?u='));
      expect(out, contains(Uri.encodeComponent('https://img.gamemale.com/a/b.png')));
    });

    test('網頁版：論壇本站的絕對網址走 /gm 轉發，**不能**丟進圖片代理', () {
      // absolute() 同時用在圖片和連結上。連結（道具的使用／購買、收藏、
      // 群組管理…）會被當成請求路徑再打一次，丟進圖片代理就會 404。
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(
        absolute('https://www.gamemale.com/home.php?mod=magic&mid=k_misign:x'),
        'https://example.test/gm/home.php?mod=magic&mid=k_misign:x',
      );
      expect(absolute('https://www.gamemale.com/forum.php'),
          'https://example.test/gm/forum.php');
    });

    test('網頁版：本站的圖片一樣走 /gm（轉發本來就處理得了）', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(absolute('https://www.gamemale.com/uc_server/avatar.php?uid=1'),
          'https://example.test/gm/uc_server/avatar.php?uid=1');
    });

    test('原生版：絕對網址原樣不動', () {
      expect(absolute('https://www.gamemale.com/forum.php'),
          'https://www.gamemale.com/forum.php');
    });

    test('網頁版：相對網址接到轉發位址底下', () {
      kOrigin = 'https://example.test/gm';
      expect(absolute('forum.php?mod=index'),
          'https://example.test/gm/forum.php?mod=index');
    });

    test('表情符號的 CDN 也走代理（不受第三方連不連得上影響）', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      final out = absolute(
          'https://gcore.jsdelivr.net/gh/googlefonts/noto-emoji/svg/emoji_u1f60d.svg');
      expect(out, startsWith('https://example.test/gmimg?u='));
    });

    test('站外的網址不動它', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(absolute('https://other.example/x.png'),
          'https://other.example/x.png');
    });

    test('data: URI 不動它', () {
      kOrigin = 'https://example.test/gm';
      expect(absolute('data:image/png;base64,AAAA'),
          'data:image/png;base64,AAAA');
    });
  });

  group('圖片跟連結要分開處理', () {
    setUp(() {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
    });
    tearDown(() {
      kOrigin = kForumOrigin;
      kAssetProxyPrefix = '';
    });

    test('第三方圖床的圖要走代理', () {
      // 帖子裡的圖常常放在 i.imgs.ovh 之類的圖床，那些沒送 CORS 標頭，
      // 直連的話瀏覽器不准 App 把圖讀進 canvas，一定顯示載入失敗。
      final out = absoluteImage('https://i.imgs.ovh/2026/08/21/x.jpg');
      expect(out, startsWith('https://example.test/gmimg?u='));
      expect(out, contains(Uri.encodeComponent('https://i.imgs.ovh/2026/08/21/x.jpg')));
    });

    test('站外**連結**不能走圖片代理', () {
      // 同一個網址如果是 <a href> 就必須原樣留著，
      // 包進圖片代理的話點下去只會拿到一張圖或一個錯誤。
      expect(absolute('https://i.imgs.ovh/2026/08/21/x.jpg'),
          'https://i.imgs.ovh/2026/08/21/x.jpg');
    });

    test('已經指到自家網域的圖不再包一層', () {
      expect(absoluteImage('https://www.gamemale.com/forum.php?mod=image&aid=1'),
          startsWith('https://example.test/gm/'));
    });

    test('data: 圖片原樣', () {
      expect(absoluteImage('data:image/png;base64,AAAA'),
          'data:image/png;base64,AAAA');
    });

    test('原生版不代理任何圖片', () {
      kOrigin = kForumOrigin;
      kAssetProxyPrefix = '';
      expect(absoluteImage('https://i.imgs.ovh/x.jpg'), 'https://i.imgs.ovh/x.jpg');
    });
  });
}
