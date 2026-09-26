import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 任務（Discuz 內建 home.php?mod=task）與每月回帖獎勵（reply_reward 外掛）。
///
/// 任務的申請／領獎／放棄都是頁面上的連結，照連結原樣 GET（不自己組網址）。
enum TaskList {
  fresh('new', '新任務'),
  doing('doing', '進行中'),
  done('done', '已完成'),
  failed('failed', '失敗');

  const TaskList(this.item, this.label);
  final String item;
  final String label;
}

class TaskLink {
  const TaskLink({required this.label, required this.url});
  final String label;
  final String url;

  /// 放棄任務要多問一次
  bool get destructive => url.contains('do=delete') || label.contains('放弃') || label.contains('放棄');
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.name,
    this.icon = '',
    this.popularity = '',
    this.description = '',
    this.reward = '',
    this.status = '',
    this.actions = const [],
  });
  final int id;
  final String name;
  final String icon;
  final String popularity;
  final String description;
  final String reward;

  /// 「完成于 2026-8-12 18:15」之類
  final String status;
  final List<TaskLink> actions;
}

class TaskListPage {
  const TaskListPage({this.items = const [], this.empty = '', this.message});
  final List<TaskItem> items;

  /// 「暂无进行中的任务…」
  final String empty;
  final String? message;
}

List<TaskLink> _links(dom.Element? scope) {
  final out = <TaskLink>[];
  for (final a in scope?.querySelectorAll('a[href*="mod=task"]') ?? const <dom.Element>[]) {
    final href = attr(a, 'href').replaceAll('&amp;', '&');
    final m = RegExp(r'do=(apply|draw|delete|giveup)').firstMatch(href);
    if (m == null) continue;
    final alt = attr(a.querySelector('img'), 'alt');
    final label = txt(a).isNotEmpty
        ? txt(a)
        : switch (m.group(1)) {
            'apply' => '立即申请',
            'draw' => '领取奖励',
            _ => '放弃任务',
          };
    out.add(TaskLink(label: sys(alt.isNotEmpty && alt != 'apply' ? alt : label), url: href));
  }
  return out;
}

Future<TaskListPage> fetchTasks(TaskList list) async =>
    parseTaskList(toDoc(await Api.instance.get('home.php?mod=task&item=${list.item}', desktop: true)));

TaskListPage parseTaskList(dom.Document doc) {
  final items = <TaskItem>[];
  for (final tr in doc.querySelectorAll('.bm.bw0 .ptm table tr')) {
    final link = tr.querySelector('h3 a');
    final id = paramInt(attr(link, 'href').replaceAll('&amp;', '&'), 'id');
    if (id == null) continue;
    final tds = tr.querySelectorAll('td');
    final last = tds.isNotEmpty ? tds.last : null;
    items.add(TaskItem(
      id: id,
      name: sys(txt(link)),
      icon: absoluteImage(attr(tr.querySelector('img'), 'src')),
      popularity: txt(tr.querySelector('h3 span a')),
      description: sys(txt(tr.querySelector('p.xg2'))),
      reward: sys(txt(tr.querySelector('td.xi1'))),
      status: sys(last == null || last.querySelector('a') != null ? '' : txt(last)),
      actions: _links(last),
    ));
  }
  return TaskListPage(
    items: items,
    empty: sys(txt(doc.querySelector('p.emp'))),
    message: items.isEmpty && doc.querySelector('p.emp') == null ? noticeMessage(doc) : null,
  );
}

class TaskDetail {
  const TaskDetail({
    required this.id,
    this.name = '',
    this.icon = '',
    this.period = '',
    this.description = '',
    this.rows = const [],
    this.status = '',
    this.progress,
    this.actions = const [],
    this.message,
  });
  final int id;
  final String name;
  final String icon;

  /// 「每周 周一 允许申请一次」
  final String period;

  /// 說明（保留換行）
  final String description;

  /// (標籤, 內容)：獎勵、完成條件、申請條件…
  final List<(String, String)> rows;

  /// 「完成于 2026-8-12 18:15 现在可以再次申请」
  final String status;

  /// 進行中才有：完成度 0～100
  final int? progress;
  final List<TaskLink> actions;
  final String? message;
}

Future<TaskDetail> fetchTask(int id) async =>
    parseTask(toDoc(await Api.instance.get('home.php?mod=task&do=view&id=$id', desktop: true)), id: id);

TaskDetail parseTask(dom.Document doc, {required int id}) {
  final box = doc.querySelector('.bm.bw0');
  final head = box?.querySelector('td.bbda');
  // 說明是 h1 後面第二個 div（第一個是週期）
  final divs = head?.children.where((e) => e.localName == 'div').toList() ?? const <dom.Element>[];
  String multiline(dom.Element? el) => el == null
      ? ''
      : el.innerHtml
          .split(RegExp(r'<br\s*/?>'))
          .map((l) => sys(txt(toDoc(l).body)))
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();

  final rows = <(String, String)>[];
  String? lastLabel;
  for (final tr in box?.querySelectorAll('table.tfm table.tfm tr') ?? const <dom.Element>[]) {
    final th = txt(tr.querySelector('th'));
    final td = sys(txt(tr.querySelector('td')));
    if (td.isEmpty) continue;
    // 沒有標題的那列是任務腳本寫的完成條件（「发新主题 1 次」），接在獎勵後面
    final label = th.isNotEmpty
        ? sys(th)
        : (lastLabel == null || lastLabel.contains(sys('奖励')) ? sys('完成条件') : lastLabel);
    rows.add((label, td));
    lastLabel = label;
  }

  final statusEl = box?.querySelector('p.xg2.mbn') ?? box?.querySelector('p.xg2');
  final pbr = box?.querySelector('.pbr');
  final pct = RegExp(r'width:\s*(\d+)%').firstMatch(attr(pbr, 'style'))?.group(1) ??
      RegExp(r'(\d+)%').firstMatch(txt(box?.querySelector('.pbg') ?? box?.querySelector('.xi1.xw1')))?.group(1);
  // 動作連結在狀態那一格
  final actionCell = statusEl?.parent ?? box;
  return TaskDetail(
    id: id,
    name: sys(txt(box?.querySelector('h1.xs2'))),
    icon: absoluteImage(attr(box?.querySelector('img[alt="Icon"]'), 'src')),
    period: sys(txt(box?.querySelector('div.xg1')).replaceAll(RegExp(r'^\(\s*|\s*\)$'), '')),
    description: multiline(divs.length > 1 ? divs[1] : (divs.isNotEmpty ? divs.first : null)),
    rows: rows,
    status: sys(txt(statusEl)),
    progress: pct == null ? null : int.tryParse(pct),
    actions: _links(actionCell),
    message: box == null ? noticeMessage(doc) : null,
  );
}

/// 申請／領獎／放棄：照頁面連結 GET，回來是一頁提示
Future<SubmitResult> taskAction(TaskLink link) async {
  final html = await Api.instance.get(link.url.replaceFirst(RegExp(r'^https?://[^/]+/'), ''), desktop: true);
  return submitResult(html, link.label);
}

// ── 每月回帖獎勵 ──────────────────────────────────────

class ReplyRewardBox {
  const ReplyRewardBox({
    required this.title,
    this.reward = '',
    this.condition = '',
    this.progressText = '',
    this.percent = 0,
    this.state = '',
    this.claim,
  });

  /// 主題獎勵／回帖獎勵
  final String title;
  final String reward;
  final String condition;
  final String progressText;
  final int percent;

  /// 「尚未完成」「已领取」
  final String state;

  /// 可以領的時候頁面上給的連結（沒看過實際長相，照原樣走）
  final TaskLink? claim;
}

class ReplyRewardPage {
  const ReplyRewardPage({this.boxes = const [], this.myInfo = const [], this.rules = const []});
  final List<ReplyRewardBox> boxes;
  final List<String> myInfo;
  final List<String> rules;
}

Future<ReplyRewardPage> fetchReplyReward() async =>
    parseReplyReward(toDoc(await Api.instance.get('plugin.php?id=reply_reward', desktop: true)));

ReplyRewardPage parseReplyReward(dom.Document doc) {
  final boxes = <ReplyRewardBox>[];
  for (final box in doc.querySelectorAll('.msgbox_7ree')) {
    final detail = box.querySelector('.detailbox_7ree');
    final ps = detail?.querySelectorAll('p') ?? const <dom.Element>[];
    final act = box.querySelector('.actbox_7ree');
    final link = act?.querySelector('a[href]');
    final btn = act?.querySelector('button, input[type="button"], input[type="submit"]');
    TaskLink? claim;
    if (link != null && !attr(link, 'href').startsWith('javascript')) {
      claim = TaskLink(label: sys(txt(link).isEmpty ? '领取' : txt(link)), url: attr(link, 'href').replaceAll('&amp;', '&'));
    } else if (btn != null) {
      final m = RegExp(r"(?:location\.href\s*=|showWindow\([^,]+,)\s*'([^']+)'").firstMatch(attr(btn, 'onclick'));
      if (m != null) claim = TaskLink(label: sys(txt(btn).isEmpty ? attr(btn, 'value') : txt(btn)), url: m.group(1)!.replaceAll('&amp;', '&'));
    }
    final h3 = detail?.querySelector('h3');
    boxes.add(ReplyRewardBox(
      title: sys(txt(h3).replaceFirst(txt(h3?.querySelector('span')), '').trim()),
      reward: sys(txt(h3?.querySelector('span'))),
      condition: sys(ps.isNotEmpty ? txt(ps[0]).replaceFirst(RegExp(r'^条件[:：]'), '') : ''),
      progressText: sys(ps.length > 1 ? txt(ps[1]).replaceFirst(RegExp(r'^进度[:：]'), '') : ''),
      percent: int.tryParse(RegExp(r'(\d+)%').firstMatch(txt(box.querySelector('.progressspan_7ree')))?.group(1) ?? '') ?? 0,
      state: sys(txt(act?.querySelector('div'))),
      claim: claim,
    ));
  }
  List<String> side(String key) {
    for (final bm in doc.querySelectorAll('.sd .bm')) {
      if (!txt(bm.querySelector('h2')).contains(key)) continue;
      return [
        for (final li in bm.querySelectorAll('li'))
          if (li.querySelector('li') == null && txt(li).isNotEmpty) sys(txt(li).replaceFirst(RegExp(r'^·\s*'), '')),
      ];
    }
    return const [];
  }

  return ReplyRewardPage(boxes: boxes, myInfo: side('我的奖励'), rules: side('活动须知'));
}

/// 獎勵歷史（類型、積分、時間）
Future<List<(String, String, String)>> fetchReplyRewardHistory() async {
  final doc = toDoc(await Api.instance.get('plugin.php?id=reply_reward&code=1', desktop: true));
  return [
    for (final tr in doc.querySelectorAll('#data_7ree tr'))
      if (tr.querySelectorAll('td') case final tds when tds.length >= 4)
        (sys(txt(tds[1])), sys(txt(tds[2])), txt(tds[3])),
  ];
}

/// 達人排行榜：(名次圖 alt 或序號, 暱稱, uid, 頭像, 說明)
Future<List<(int, String, int?, String, String)>> fetchReplyRewardRank() async {
  final doc = toDoc(await Api.instance.get('plugin.php?id=reply_reward&code=2', desktop: true));
  final out = <(int, String, int?, String, String)>[];
  var i = 0;
  for (final dl in doc.querySelectorAll('.ranklist_7ree')) {
    i++;
    final a = dl.querySelector('dd p a');
    out.add((
      i,
      txt(a),
      int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? ''),
      absoluteImage(attr(dl.querySelector('.avt img'), 'src')),
      sys(txt(dl.querySelectorAll('dd p').length > 1 ? dl.querySelectorAll('dd p')[1] : null)),
    ));
  }
  return out;
}
