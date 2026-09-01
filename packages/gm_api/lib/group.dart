import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 群組。這站的群組只有桌面模板 —— 帶 mobile=2 一律回錯誤頁，
/// 所以 App 走 `/f/<fid>` 進來會看到「這個板塊沒有主題」。
Future<GroupData> fetchGroup(int fid, {int page = 1}) async {
  final html = await Api.instance.get('group-$fid-$page.html', desktop: true);
  return parseGroup(toDoc(html), html, fid, page: page);
}

GroupData parseGroup(dom.Document doc, String html, int fid, {int page = 1}) {
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

  // 已加入＝有「發帖」按鈕、沒有「加入群组」按鈕
  final joined = !joinable && html.contains('action=newthread');

  // 群主／積分／等級在 dd.cl 那一行
  final metaDd = doc.querySelector('.bm_c dl dd.cl');
  final masterLink = metaDd?.querySelector('a[href*="space-uid"]');
  final level =
      attr(metaDd?.querySelector('img[title*="群组等级"], img[title*="群組等級"]'), 'title');
  final pointsM = RegExp(r'积分[:：]\s*(\d+)').firstMatch(txt(metaDd));
  final fav = doc.querySelector('#a_favorite');

  return GroupData(
    fid: fid,
    name: name,
    icon: absolute(attr(doc.querySelector('.bm_c dl dd img'), 'src')),
    desc: txt(doc.querySelector('.bm_c dl dd:not(.m):not(.cl)')),
    meta: txt(metaDd),
    master: txt(masterLink),
    masterUid: paramInt(attr(masterLink, 'href'), 'uid') ??
        int.tryParse(
            RegExp(r'space-uid-(\d+)').firstMatch(attr(masterLink, 'href'))?.group(1) ?? ''),
    level: level.replaceAll(RegExp(r'^群[组組]等[级級][:：]?\s*'), ''),
    points: pointsM?.group(1) ?? '',
    joined: joined,
    favoriteUrl: absolute(attr(fav, 'href')),
    formhash: formhashOf(doc, html) ?? '',
    threads: threads,
    pager: parsePager(doc, current: page),
    canJoin: joinable,
    message: threads.isEmpty
        ? (noticeMessage(doc) ??
            (joinable
                ? '要先加入這個群組才看得到裡面的主題'
                : '這個群組沒有開放給你，或還沒有主題'))
        : null,
  );
}

/// 群組首頁：推薦群組、群組分類、積分排行
Future<GroupIndex> fetchGroupIndex() async {
  final doc = toDoc(await Api.instance.get('group.php?mod=index', desktop: true));
  return parseGroupIndexDoc(doc);
}

GroupIndex parseGroupIndexDoc(dom.Document doc) {
  // 推薦群組
  final recommended = <GroupItem>[];
  for (final dl in doc.querySelectorAll('#g_commend .xld, .bm_c .xld')) {
    final a = dl.querySelector('dt a[href*="group-"]') ??
        dl.querySelector('a[href*="group-"]');
    final gid = int.tryParse(
        RegExp(r'group-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    if (a == null || gid == null) continue;
    if (recommended.any((g) => g.fid == gid)) continue;
    final dds = dl.querySelectorAll('dd');
    recommended.add(GroupItem(
      fid: gid,
      name: txt(a),
      icon: absolute(attr(dl.querySelector('dd.m img') ?? dl.querySelector('img'), 'src')),
      desc: dds.length > 1 ? txt(dds.last) : '',
    ));
  }

  // 群組分類
  final categories = <GroupCategory>[];
  for (final dl in doc.querySelectorAll('.bm_c dl.mbm')) {
    final head = dl.querySelector('dt strong a') ?? dl.querySelector('dt a');
    final name = txt(head);
    if (name.isEmpty) continue;
    final subs = <({String name, int? sgid, int? gid})>[];
    for (final s in dl.querySelectorAll('dt .y a')) {
      final label = txt(s);
      if (label.isEmpty || label.contains('更多')) continue;
      subs.add((
        name: label,
        sgid: paramInt(attr(s, 'href'), 'sgid'),
        gid: paramInt(attr(s, 'href'), 'gid'),
      ));
    }
    final groups = <GroupItem>[];
    for (final g in dl.querySelectorAll('dd a[href*="group-"]')) {
      final gid = int.tryParse(
          RegExp(r'group-(\d+)').firstMatch(attr(g, 'href'))?.group(1) ?? '');
      if (gid == null || groups.any((x) => x.fid == gid)) continue;
      groups.add(GroupItem(fid: gid, name: txt(g)));
    }
    categories.add(GroupCategory(
      name: name,
      count: txt(dl.querySelector('dt .xg1')).replaceAll(RegExp(r'[()（）]'), ''),
      subs: subs,
      groups: groups,
    ));
  }

  // 積分排行
  final ranking = <GroupRankRow>[];
  var rank = 0;
  for (final li in doc.querySelectorAll('.wp-side ol.xl li, ol.xl li')) {
    final a = li.querySelector('a[href*="group-"]');
    final fid = int.tryParse(
        RegExp(r'group-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    if (a == null || fid == null) continue;
    rank++;
    ranking.add(GroupRankRow(
      rank: rank,
      name: txt(a),
      fid: fid,
      points: txt(li.querySelector('.y')),
    ));
  }

  return GroupIndex(
      recommended: recommended, categories: categories, ranking: ranking);
}

/// 我的群組。view: join（我參與的）/ manager（我管理的）
Future<List<GroupItem>> fetchMyGroups({String view = 'join'}) async {
  final doc = toDoc(
      await Api.instance.get('group.php?mod=my&view=$view', desktop: true));
  final out = <GroupItem>[];
  for (final dl in doc.querySelectorAll('.xld, .flg dl, li')) {
    final a = dl.querySelector('a[href*="group-"]');
    final gid = int.tryParse(
        RegExp(r'group-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    if (a == null || gid == null) continue;
    final name = txt(a);
    if (name.isEmpty || out.any((g) => g.fid == gid)) continue;
    out.add(GroupItem(
      fid: gid,
      name: name,
      icon: absolute(attr(dl.querySelector('img'), 'src')),
    ));
  }
  return out;
}

/// 群組成員清單
Future<({List<GroupMember> members, PageInfo pager})> fetchGroupMembers(
    int fid,
    {int page = 1}) async {
  final doc = toDoc(await Api.instance.get(
      'forum.php?mod=group&action=memberlist&fid=$fid${page > 1 ? '&page=$page' : ''}',
      desktop: true));
  return parseGroupMembersDoc(doc, page: page);
}

({List<GroupMember> members, PageInfo pager}) parseGroupMembersDoc(
    dom.Document doc,
    {int page = 1}) {
  final out = <GroupMember>[];
  for (final li in doc.querySelectorAll('ul.ml li')) {
    final avt = li.querySelector('a.avt');
    final nameLink = li.querySelector('p a') ?? avt;
    final name = txt(nameLink);
    if (name.isEmpty) continue;
    out.add(GroupMember(
      name: name,
      uid: paramInt(attr(nameLink, 'href'), 'uid') ??
          int.tryParse(
              RegExp(r'space-uid-(\d+)').firstMatch(attr(nameLink, 'href'))?.group(1) ?? ''),
      avatar: absolute(attr(li.querySelector('img'), 'src')),
      title: attr(avt, 'title'),
    ));
  }
  return (members: out, pager: parsePager(doc, current: page));
}

/// 加入群組。論壇這個連結是一步就加入（沒有確認頁），呼叫端要先問使用者
Future<SubmitResult> joinGroup(int fid) async {
  final html =
      await Api.instance.get('forum.php?mod=group&action=join&fid=$fid', desktop: true);
  return submitResult(html, '加入群組');
}

/// 退出群組。POST action=out + groupexit=1
Future<SubmitResult> quitGroup(int fid, {required String formhash}) async {
  final html = await Api.instance.post(
    'forum.php?mod=group&action=out&fid=$fid',
    {'formhash': formhash, 'groupexit': '1'},
    desktop: true,
  );
  return submitResult(html, '退出群組');
}

/// 群組列表（相容舊呼叫）：現在回推薦群組
Future<List<GroupItem>> fetchGroups() async {
  final idx = await fetchGroupIndex();
  return idx.recommended;
}
