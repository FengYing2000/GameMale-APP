import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/parse.dart';
import 'package:test/test.dart';

/// 桌面版提示頁（showmessage）的骨架，取自真實的 thread-195793（閱讀權限不足）。
/// 重點是開頭那段隱藏的 #main_succeed：裡面有空的 .alert_right 跟一行
/// 「如果您的浏览器没有自动跳转」，真正的訊息在後面的 #messagetext。
String _desktopMessage(String msg, {String kind = 'alert_info'}) => '''
<html><body><div id="ct" class="wp cl w">
<div class="nfl" id="main_succeed" style="display: none"><div class="f_c altw">
<div class="alert_right"><p id="succeedmessage"></p><p id="succeedlocation" class="alert_btnleft"></p>
<p class="alert_btnleft"><a id="succeedmessage_href">如果您的浏览器没有自动跳转，请点击此链接</a></p>
</div></div></div>
<div class="nfl" id="main_message"><div class="f_c altw">
<div id="messagetext" class="$kind"><p>$msg</p></div>
<div id="messagelogin"></div>
</div></div></div>
<a href="member.php?mod=logging&action=logout&formhash=abcd1234">退出</a>
</body></html>''';

/// 手機版提示頁（xinrui 模板的 jump_c）
String _mobileMessage(String msg) => '''
<html><body><header class="header"><h1 class="logo"><img src="logo.png"></h1></header>
<div class="jump_c"><p class="del_tips"><span class="alert_error">$msg</span></p>
<p><a class="btn4" href="javascript:history.back()">返回</a></p></div>
<a href="member.php?mod=logging&action=logout&formhash=abcd1234">退出</a>
</body></html>''';

void main() {
  group('提示頁訊息', () {
    test('桌面版抓 #messagetext，不抓隱藏的 #main_succeed', () {
      final doc = toDoc(_desktopMessage('抱歉，本帖要求阅读权限高于 105 才能浏览'));
      final n = noticeOf(doc)!;
      expect(n.text, '抱歉，本帖要求阅读权限高于 105 才能浏览');
      expect(n.kind, 'info');
    });

    test('手機版 del_tips 內層的 alert_error', () {
      final n = noticeOf(toDoc(_mobileMessage('抱歉，本主题已关闭，不能再回复')))!;
      expect(n.text, '抱歉，本主题已关闭，不能再回复');
      expect(n.kind, 'error');
    });
  });

  group('回帖送出結果', () {
    test('論壇擋下的提示不能再被當成功（整頁比對 succeed 的舊 bug）', () {
      final r = api.submitResult(
          _desktopMessage('您今日在本版块的回帖数量已达上限'), '回覆',
          expectThread: true);
      expect(r.ok, isFalse);
      expect(r.unsure, isTrue, reason: '字句不在失敗清單裡，要再去帖子確認');
      expect(r.message, '您今日在本版块的回帖数量已达上限');
    });

    test('已知失敗字句直接判失敗，不必再確認', () {
      final r = api.submitResult(
          _desktopMessage('抱歉，您的帖子小于 25 个字符的限制'), '回覆',
          expectThread: true);
      expect(r.ok, isFalse);
      expect(r.unsure, isFalse);
    });

    test('alert_right 是成功（例如回覆送審）', () {
      final r = api.submitResult(
          _desktopMessage('新回复需要审核，您的帖子通过审核后才能显示',
              kind: 'alert_right'),
          '回覆',
          expectThread: true);
      expect(r.ok, isTrue);
    });

    test('落在帖子頁就是成功', () {
      final r = api.submitResult(
          '<html><body><div id="postlist"></div></body></html>', '回覆',
          expectThread: true);
      expect(r.ok, isTrue);
      expect(r.unsure, isFalse);
    });

    test('其他動作遇到看不懂的提示維持舊行為（照原文、當成功）', () {
      final r = api.submitResult(_desktopMessage('已处理'), '收藏');
      expect(r.ok, isTrue);
      expect(r.message, '已处理');
    });
  });

  group('帖子頁', () {
    test('閱讀權限不足：沒有樓層，帶出論壇的提示', () {
      final d = api.parseThread(
          toDoc(_mobileMessage('抱歉，本帖要求阅读权限高于 105 才能浏览')), 195793);
      expect(d.posts, isEmpty);
      expect(d.message, '抱歉，本帖要求阅读权限高于 105 才能浏览');
    });

    test('桌面版回帖框「您现在无权发帖」', () {
      final doc = toDoc('''<html><body>
<div id="f_pst" class="pl bm bmw"><form id="fastpostform" method="post">
<div class="area"><div class="pt hm">您现在无权发帖。<a href="javascript:;"
 onclick="\$('fastpostform').submit()" class="xi2">点击查看原因</a></div></div>
</form></div></body></html>''');
      expect(api.replyBlockedOf(doc), '您现在无权发帖');
    });

    test('帖子內容寫到「无权发帖」不算', () {
      final doc = toDoc('''<html><body>
<td class="t_f">为什么我现在无权发帖？</td>
<div id="f_pst"><form id="fastpostform"><textarea name="message" id="fastpostmessage"></textarea></form></div>
</body></html>''');
      expect(api.replyBlockedOf(doc), '');
    });
  });

  group('回覆表單（能不能回＋字數限制）', () {
    test('有表單：讀 postminchars／postmaxchars', () {
      final g = api.parseReplyGate('''<html><body>
<form id="postform"><textarea name="message" id="e_textarea"></textarea></form>
<script>var postminchars = parseInt('25');
var postmaxchars = parseInt('50000');
var disablepostctrl = parseInt('0');</script></body></html>''');
      expect(g.allowed, isTrue);
      expect(g.minBytes, 25);
      expect(g.maxBytes, 50000);
    });

    test('用戶組不受字數限制（disablepostctrl=1）', () {
      final g = api.parseReplyGate('''<html><body>
<textarea name="message"></textarea>
<script>var postminchars = parseInt('25'); var postmaxchars = parseInt('50000');
var disablepostctrl = parseInt('1');</script></body></html>''');
      expect(g.minBytes, 0);
      expect(g.maxBytes, 0);
    });

    test('沒表單、有提示：不能回，原因照給', () {
      final g = api.parseReplyGate(_desktopMessage('抱歉，本主题已关闭，不能再回复'));
      expect(g.allowed, isFalse);
      expect(g.message, '抱歉，本主题已关闭，不能再回复');
    });

    test('看不懂的頁面不擋', () {
      expect(api.parseReplyGate('<html><body></body></html>').allowed, isTrue);
    });
  });

  group('字數與確認', () {
    test('論壇用 UTF-8 位元組算：中文 3、英數 1', () {
      expect(api.postBytes('中a'), 4);
      expect(api.postBytes('感谢分享，内容非常精彩！'), 36);
    });

    test('認回覆用的純文字去掉 BBCode／表情／引用', () {
      expect(
          api.replyProbe('[quote]别人说的[/quote]\n[b]谢谢[/b] 楼主{:6_180:} 分享'),
          '谢谢楼主分享');
      expect(api.replyProbe('{:6_180:}{:6_190:}'), '');
      expect(api.replyProbe('一' * 30).length, 20);
    });
  });

  group('「已回」判定（authorid=自己）', () {
    test('有樓層才算回過', () {
      final r = api.parseAuthorView(
          '<html><body><div class="postListItem" id="pid1"></div></body></html>');
      expect(r.replied, isTrue);
    });

    test('未定义操作＝沒回過', () {
      expect(api.parseAuthorView(_mobileMessage('未定义操作')).replied, isFalse);
    });

    test('閱讀權限不足不能標成已回，並記下要求的權限', () {
      final r = api.parseAuthorView(
          _mobileMessage('抱歉，本帖要求阅读权限高于 105 才能浏览'));
      expect(r.replied, isFalse, reason: '以前沒看到「未定义操作」就當回過');
      expect(r.readPerm, 105);
    });

    test('帖子被刪的提示頁也不算回過', () {
      final r = api.parseAuthorView(
          _mobileMessage('抱歉，指定的主题不存在或已被删除或正在被审核'));
      expect(r.replied, isFalse);
      expect(r.readPerm, 0);
    });
  });

  group('桌面版列表標記', () {
    test('閱讀權限與關閉的主題', () {
      final row = toDoc('''<table><tbody id="normalthread_10379"><tr>
<td class="icn"><a href="x" title="关闭的主题 - 新窗口打开"><img src="static/image/common//folder_lock.gif"></a></td>
<th><a href="thread-10379-1-1.html" class="xst">徽章审核恢复</a>
 - [阅读权限 <span class="xw1">105</span>]</th></tr></tbody></table>''')
          .querySelector('tbody')!;
      final f = threadRowFlags(row);
      expect(f.readPerm, 105);
      expect(f.closed, isTrue);
    });

    test('一般主題沒有標記', () {
      final row = toDoc('''<table><tr><td class="icn"><img src="static/image/common//folder_common.gif"></td>
<th><a href="thread-1-1-1.html" class="xst">一般</a></th></tr></table>''')
          .querySelector('tr')!;
      final f = threadRowFlags(row);
      expect(f.readPerm, 0);
      expect(f.closed, isFalse);
    });
  });
}
