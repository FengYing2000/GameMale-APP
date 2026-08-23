import 'package:html/dom.dart' as dom;

import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 群組。這站的群組只有桌面模板 —— 帶 mobile=2 一律回錯誤頁，
/// 所以 App 走 `/f/<fid>` 進來會看到「這個板塊沒有主題」。
Future<GroupData> fetchGroup(int fid, {int page = 1}) async {
  final html = await Api.instance.get('group-$fid-$page.html', desktop: true);
  return parseGroup(toDoc(html), html, fid);
}

GroupData parseGroup(dom.Document doc, String html, int fid) {
  if (isLoginWall(doc) || isRedirectToLogin(doc, html)) {
    return const GroupData(message: '要先登入才看得到這個群組', needsLogin: true);
  }

  // 已加入的群組名字在 dl dt；沒加入的那版 #gh h1 有時是站方公告，
  // 所以拿 <title>「群組名 - GameMale」當保底
  final titleName =
      RegExp(r'^(.*?)\s*-').firstMatch(txt(doc.querySelector('title')))?.group(1) ??
          '';
  final dtName = txt(doc.querySelector('.bm_c dl dt'));
  final name = dtName.isNotEmpty ? dtName : titleName;

  final threads = <ThreadItem>[];
  for (final tr in doc.querySelectorAll('.tl tr')) {
    final a = tr.querySelector('th a');
    if (a == null) continue;
    final tid = int.tryParse(
        RegExp(r'thread-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    if (tid == null) continue;
    final by = tr.querySelectorAll('td.by');
    final num = tr.querySelector('td.num');
    threads.add(ThreadItem(
      tid: tid,
      title: txt(a),
      author: by.isEmpty ? '' : txt(by.first.querySelector('cite')),
      date: by.isEmpty ? '' : txt(by.first.querySelector('em')),
      replies: int.tryParse(txt(num?.querySelector('a'))) ?? 0,
      views: int.tryParse(txt(num?.querySelector('em'))) ?? 0,
    ));
  }

  // 沒加入或沒權限的群組看不到主題，論壇改成只顯示介紹與加入按鈕
  final joinable = doc.querySelector('button[onclick*="action=join"]') != null ||
      html.contains('mod=group&action=join');

  return GroupData(
    fid: fid,
    name: name,
    icon: absolute(attr(doc.querySelector('.bm_c dl dd img'), 'src')),
    desc: txt(doc.querySelector('.bm_c dl dd:not(.m):not(.cl)')),
    meta: txt(doc.querySelector('.bm_c dl dd.cl')),
    threads: threads,
    pager: parsePager(doc),
    canJoin: joinable,
    message: threads.isEmpty
        ? (noticeMessage(doc) ??
            (joinable
                ? '要先加入這個群組才看得到裡面的主題'
                : '這個群組沒有開放給你，或還沒有主題'))
        : null,
  );
}

/// 群組列表（group.php）
Future<List<GroupItem>> fetchGroups() async {
  final doc = toDoc(await Api.instance.get('group.php', desktop: true));
  final out = <GroupItem>[];
  for (final a in doc.querySelectorAll('a[href*="group-"]')) {
    final gid = int.tryParse(
        RegExp(r'group-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    final label = txt(a);
    if (gid == null || label.isEmpty) continue;
    if (out.any((g) => g.fid == gid)) continue;
    out.add(GroupItem(
      fid: gid,
      name: label,
      icon: absolute(attr(a.querySelector('img'), 'src')),
    ));
  }
  return out;
}
