import 'package:gm_api/discuz.dart';
import 'package:gm_api/parse.dart';
import 'package:test/test.dart';

/// 樣本取自論壇桌面版首頁的 `#online` 區塊。
void main() {
  const html = '''
<div id="online" class="bm oll">
<div class="bm_h">
<h2><strong><a href="https://www.gamemale.com/home.php?mod=space&amp;do=friend&amp;view=online&amp;type=member">在线会员</a></strong></h2>
<span class="xs1"><strong>464</strong> 人在线
- <strong>302</strong> 会员(<strong>20</strong> 隐身),
<strong>162</strong> 位游客
- 最高记录是 <strong>45510</strong> 于 <strong>2026-9-4</strong>.</span>
</div>
<dl id="onlinelist" class="bm_c">
<dt class="ptm pbm bbda"><img src="static/image/common/online_admin.gif"> 村委</dt>
<dd class="ptm pbm">
<ul class="cl">
<li title="时间: 22:21"><img src="static/image/common/online_member.gif" alt="icon">
<a href="https://www.gamemale.com/space-uid-677863.html">FengYing</a></li>
<li title="时间: 22:16"><img src="static/image/common/online_supermod.gif" alt="icon">
<a href="https://www.gamemale.com/space-uid-695182.html">XLK</a></li>
<li title="时间: 22:16"><img src="static/image/common/online_member.gif" alt="icon">
<a href="https://www.gamemale.com/space-uid-719324.html">oo98ii</a></li>
<li title="时间: 22:16"><img src="static/image/common/online_member.gif" alt="icon">
<a href="https://www.gamemale.com/space-uid-719324.html">oo98ii</a></li>
</ul>
</dd>
</dl>
</div>
''';

  group('在線會員的統計數字', () {
    final info = parseIndexOnline(toDoc(html));

    test('四個數字都對得上', () {
      expect(info.total, 464);
      expect(info.members, 302);
      expect(info.invisible, 20);
      expect(info.guests, 162);
    });

    test('歷史最高紀錄與日期', () {
      expect(info.record, 45510);
      expect(info.recordDate, '2026-9-4');
    });

    test('沒有隱身會員時不能錯位', () {
      // 隱身數是 0 時論壇不輸出那一段。照 <strong> 的順序取值的話，
      // 訪客數會被當成隱身數，整排往前錯一格。
      final s = parseIndexOnline(toDoc('''
<div id="online"><div class="bm_h"><span class="xs1">
<strong>50</strong> 人在线 - <strong>30</strong> 会员, <strong>20</strong> 位游客
- 最高记录是 <strong>999</strong> 于 <strong>2026-1-1</strong>.</span></div></div>'''));
      expect(s.total, 50);
      expect(s.members, 30);
      expect(s.invisible, 0);
      expect(s.guests, 20, reason: '訪客數不能被隱身那一格吃掉');
    });
  });

  group('在線名單', () {
    final info = parseIndexOnline(toDoc(html));

    test('讀得到 uid、名字與身分', () {
      expect(info.users.first.uid, 677863);
      expect(info.users.first.name, 'FengYing');
      expect(info.users.first.group, 'member');
      expect(info.users.first.time, '22:21');
      expect(info.users[1].group, 'supermod', reason: '身分取自圖示檔名');
    });

    test('同一個人列兩次要去重', () {
      // 論壇對多個工作階段會重複列出，照搬會看起來像我們的 bug
      expect(info.users.length, 3);
      expect(info.users.where((u) => u.uid == 719324).length, 1);
    });
  });

  group('沒有這個區塊時安靜地回空的', () {
    test('論壇關掉在線列表也不能炸', () {
      final none = parseIndexOnline(toDoc('<div id="ft">頁尾</div>'));
      expect(none.isEmpty, isTrue);
      expect(none.users, isEmpty);
    });
  });

  group('收合／未登入時的形狀（實測訪客版就是這樣）', () {
    // 首頁預設是收合的，論壇只吐「总计 N 人在线 - 最高记录是 …」，
    // 既沒有會員／訪客的細分，也沒有名單。
    final info = parseIndexOnline(toDoc(
      '<div id="online" class="bm oll"><div class="bm_h">'
      '<h2><strong>在线会员</strong></h2>'
      '<span class="xs1">总计 <strong>3193</strong> 人在线'
      ' - 最高记录是 <strong>45510</strong> 于 <strong>2026-9-4</strong>.'
      '</span></div></div>',
    ));

    test('總人數與紀錄讀得到', () {
      expect(info.total, 3193);
      expect(info.record, 45510);
      expect(info.recordDate, '2026-9-4');
    });

    test('沒有細分時要講得出來', () {
      // 這時顯示「會員 0 · 訪客 0」是錯的，介面靠這個旗標整行不顯示
      expect(info.hasBreakdown, isFalse);
      expect(info.users, isEmpty);
    });

    test('但不算空的——總人數還是有意義', () {
      expect(info.isEmpty, isFalse);
    });
  });
}
