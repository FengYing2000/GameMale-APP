import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/parse.dart';
import 'package:gm_api/s2t.dart';
import 'package:test/test.dart';

/// 這支測試存在的理由：證明 Flutter App 那 6000 多行論壇解析，
/// 真的能在純 Dart 的伺服器上原封不動跑起來。
///
/// 如果哪天有人在 gm_api 裡不小心 import 了 Flutter 的東西，
/// 這裡會第一個編不過。
void main() {
  _proxyQuery();

  group('共用解析層在伺服器端能跑', () {
    test('頁首提醒選單的未讀數', () {
      // 這是論壇桌面版頁首 #myprompt_menu 的結構
      final doc = toDoc('''
        <div id="myprompt" class="showmenu yes">提醒</div>
        <div id="myprompt_menu">
          <ul>
            <li><a href="home.php?mod=space&do=pm" class="prompt_news_3">
              私信<span class="rq">3</span></a></li>
            <li><a href="home.php?mod=space&do=notice&view=mypost">
              帖子<span class="rq">2</span></a></li>
            <li><a href="home.php?mod=space&do=notice&view=system">
              系统<span class="rq">1</span></a></li>
            <li><a href="home.php?mod=space&do=follow" class="prompt_follower_1">
              好友</a></li>
          </ul>
        </div>
      ''');

      final b = api.parsePromptCounts(doc);
      expect(b.pm, 3, reason: '私訊數要從 prompt_news_N 的後綴讀');
      expect(b.views, {'mypost': 2, 'system': 1});
      expect(b.notice, 4, reason: '各類提醒 2+1 再加上好友請求 1');
    });

    test('沒有未讀時全是 0', () {
      final doc = toDoc('''
        <div id="myprompt" class="showmenu">提醒</div>
        <div id="myprompt_menu">
          <ul><li><a href="home.php?mod=space&do=pm">私信</a></li></ul>
        </div>
      ''');
      final b = api.parsePromptCounts(doc);
      expect(b.notice, 0);
      expect(b.pm, 0);
      expect(b.views, isEmpty);
    });

    test('只有 myprompt 亮著、數字讀不到時，至少要算 1 則', () {
      // 論壇偶爾只給 class="yes" 不給數字，這時不能當成沒有通知
      final doc = toDoc('''
        <div id="myprompt" class="showmenu yes">提醒</div>
        <div id="myprompt_menu"><ul></ul></div>
      ''');
      expect(api.parsePromptCounts(doc).notice, 1);
    });
  });

  group('簡繁轉換沒注入時要安靜地原樣輸出', () {
    test('對照表沒載入也不會丟例外，原樣回傳', () {
      // 伺服器上讀不到 s2t.json 時走的就是這條：
      // 通知會是簡體而不是繁體，但服務不能因此掛掉
      expect(S2T.instance.ready, isFalse);
      expect(sys('汉化补丁'), '汉化补丁');
      expect(zh('汉化补丁'), '汉化补丁');
    });
  });
}

void _proxyQuery() {
  group('轉發要保留原始 query', () {
    // 論壇有些網址會帶重複參數（`&mobile=no&mobile=2`）。用 Map 重建會
    // 只留最後一個，論壇因此回不同模板，解析器就抓不到東西。
    test('重複的參數不能被吃掉', () {
      final url = Uri.parse('/gm/home.php?mod=space&do=doing&mobile=no&mobile=2');
      // Map 會把重複的 key 壓成一個——這正是不能用它的原因
      expect(url.queryParameters['mobile'], '2');
      expect(url.queryParametersAll['mobile'], ['no', '2']);
      // 原始字串則完整保留
      expect(url.query, contains('mobile=no'));
      expect(url.query, contains('mobile=2'));
    });
  });
}
