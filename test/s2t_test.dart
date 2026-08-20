// 簡繁轉換：確認詞表優先於單字表，且不會誤轉。
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/i18n/s2t.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => S2T.instance.load());

  test('對照表載得起來', () {
    expect(S2T.instance.ready, isTrue);
  });

  test('逐字轉換會轉錯的詞，靠詞表救回來', () {
    // 发 單獨可以是 發 或 髮，要看詞
    expect(S2T.instance.convert('头发'), '頭髮');
    expect(S2T.instance.convert('发布'), '發佈');
    // 干 可以是 乾 / 幹 / 干
    expect(S2T.instance.convert('干净'), '乾淨');
    // 面 可以是 面 / 麵
    expect(S2T.instance.convert('面条'), '麵條');
  });

  test('本來就正確的字不要亂轉', () {
    expect(S2T.instance.convert('皇后'), '皇后');
    expect(S2T.instance.convert('皇后娘娘'), '皇后娘娘');
  });

  test('論壇常見用語', () {
    expect(S2T.instance.convert('记录广场'), '記錄廣場');
    expect(S2T.instance.convert('坛友互动'), '壇友互動');
    expect(S2T.instance.convert('系统提醒'), '系統提醒');
    expect(S2T.instance.convert('已签到'), '已簽到');
  });

  test('非中文與標點原樣保留', () {
    expect(S2T.instance.convert('GameMale 2026!'), 'GameMale 2026!');
    expect(S2T.instance.convert(''), '');
  });

  test('繁體輸入不會被破壞', () {
    expect(S2T.instance.convert('這裡是繁體字'), '這裡是繁體字');
  });
}
