import 'package:gm_api/http.dart';
import 'package:gm_api/parse.dart';
import 'package:test/test.dart';

/// 表情符號要畫小、內容圖要畫大，而那個判斷是**比對網址字串**做的。
/// 網頁版會把網址改寫成走代理（論壇本站→/gm/…、外部子網域與 emoji CDN
/// →/gmimg?u=<編碼後的原網址>），所以只要動到改寫規則就可能悄悄破壞
/// 尺寸判斷——之前就發生過「帖內表情圖變成整排大圖」。這裡把它釘住。
void main() {
  group('表情符號在代理模式下仍被判定為小圖', () {
    tearDown(() {
      kOrigin = kForumOrigin;
      kAssetProxyPrefix = '';
    });

    String classOf(String html) {
      final out = sanitizeContent(toDoc(html).body);
      final m = RegExp(r'class="([^"]*)"').firstMatch(out);
      return m?.group(1) ?? '';
    }

    test('原生版：論壇自己的表情', () {
      expect(
        classOf('<img src="https://www.gamemale.com/static/image/smiley/'
            'default/dizzy.gif" width="15">'),
        'smiley',
      );
    });

    test('網頁版：論壇的表情走 /gm 之後還認得出來', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(
        classOf('<img src="https://www.gamemale.com/static/image/smiley/'
            'default/dizzy.gif" width="15">'),
        'smiley',
      );
    });

    test('網頁版：noto-emoji 走 /gmimg（網址被編碼）之後還認得出來', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(
        classOf('<img src="https://gcore.jsdelivr.net/gh/googlefonts/'
            'noto-emoji/svg/emoji_u1f60d.svg" width="15">'),
        'smiley',
      );
    });

    test('真正的內容圖不能被誤判成表情', () {
      kOrigin = 'https://example.test/gm';
      kAssetProxyPrefix = 'https://example.test/gmimg?u=';
      expect(
        classOf('<img src="https://img.gamemale.com/forum/202608/23/'
            'x.jpg" width="800">'),
        'post-img',
      );
    });
  });
}
