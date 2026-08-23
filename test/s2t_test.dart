// 簡→繁（台灣用語）。規則寫在 tool/zh_rules.py，改完要跑 build_zh_table.py 重產。
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/i18n/s2t.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => S2T.instance.load());

  String c(String s) => S2T.instance.convert(s);

  test('對照表載得起來', () => expect(S2T.instance.ready, isTrue));

  group('一對多的字：逐字會賭錯邊，靠詞救回來', () {
    test('发 → 發 / 髮', () {
      expect(c('发表回复'), '發表回覆');
      expect(c('头发'), '頭髮');
      expect(c('理发店'), '理髮店');
    });
    test('干 → 幹 / 乾', () {
      expect(c('干嘛'), '幹嘛');
      expect(c('干净'), '乾淨');
      expect(c('饼干'), '餅乾');
    });
    test('面 → 面 / 麵', () {
      expect(c('当面'), '當面');
      expect(c('面条'), '麵條');
      expect(c('泡面'), '泡麵');
    });
    test('复 → 復 / 複 / 覆', () {
      expect(c('回复'), '回覆');
      expect(c('复制'), '複製');
      expect(c('恢复'), '恢復');
    });
    test('签 → 簽 / 籤', () {
      expect(c('签到'), '簽到');
      expect(c('抽签'), '抽籤');
      expect(c('标签'), '標籤');
    });
    test('游 → 遊 / 游', () {
      expect(c('游戏'), '遊戲');
      expect(c('游泳'), '游泳');
    });
    test('斗 → 鬥 / 斗', () {
      expect(c('战斗'), '戰鬥');
      expect(c('北斗'), '北斗');
    });
    test('尽 → 盡 / 儘', () {
      expect(c('尽力'), '盡力');
      expect(c('尽管'), '儘管');
    });
  });

  group('排除轉換的字：另一義要靠詞補回來', () {
    test('里：里程不轉，裡面要轉', () {
      expect(c('旅程 295 里'), '旅程 295 里');
      expect(c('公里'), '公里');
      expect(c('这里'), '這裡');
      expect(c('心里'), '心裡');
    });
    test('范：姓氏不轉，範圍要轉', () {
      expect(c('范围'), '範圍');
      expect(c('规范'), '規範');
    });
    test('谷：山谷不轉，穀物要轉', () {
      expect(c('山谷'), '山谷');
      expect(c('谷物'), '穀物');
    });
    test('尸：屍體要轉', () {
      expect(c('尸体'), '屍體');
      expect(c('僵尸'), '殭屍');
    });
    test('台：台灣不寫臺，颱風要轉', () {
      expect(c('台湾'), '台灣');
      expect(c('台风'), '颱風');
    });
  });

  group('台灣用語（要開了才會換詞）', () {
    setUp(() => S2T.instance.useTaiwanWords = true);
    tearDown(() => S2T.instance.useTaiwanWords = false);

    test('電腦網路', () {
      expect(c('软件'), '軟體');
      expect(c('硬盘'), '硬碟');
      expect(c('网络'), '網路');
      expect(c('鼠标'), '滑鼠');
      expect(c('屏幕'), '螢幕');
      expect(c('内存'), '記憶體');
      expect(c('文件夹'), '資料夾');
      expect(c('打印机'), '印表機');
      expect(c('默认'), '預設');
      expect(c('链接'), '連結');
    });
    test('論壇常見', () {
      expect(c('视频'), '影片');
      expect(c('信息'), '訊息');
      expect(c('质量'), '品質');
      expect(c('举报'), '檢舉');
      expect(c('屏蔽'), '封鎖');
      expect(c('点赞'), '按讚');
    });
  });

  group('關掉台灣用語時只做字形轉換', () {
    // 換詞會改掉論壇原本的用字，帖子標題就跟網頁版對不起來
    test('用詞維持原樣', () {
      expect(c('软件'), '軟件');
      expect(c('视频'), '視頻');
      expect(c('默认'), '默認');
    });
    test('字形照樣轉，消歧義也還在', () {
      expect(c('发表回复'), '發表回覆');
      expect(c('头发'), '頭髮');
      expect(c('这里'), '這裡');
    });
    test('汉化不會變成中文化 —— 台灣也講漢化，換掉只會對不上論壇原文', () {
      expect(c('汉化'), '漢化');
      S2T.instance.useTaiwanWords = true;
      expect(c('汉化'), '漢化');
      S2T.instance.useTaiwanWords = false;
    });
  });

  group('不該動的東西', () {
    test('本來就是繁體不會被破壞', () {
      expect(c('這裡是繁體字'), '這裡是繁體字');
    });
    test('英數與標點原樣保留', () {
      expect(c('GameMale 2026!'), 'GameMale 2026!');
      expect(c(''), '');
    });
  });
}
