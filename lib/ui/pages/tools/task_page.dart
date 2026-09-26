import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/task.dart' as api;
import '../../../i18n/ui.dart';
import '../../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/state_box.dart';

/// 申請／領獎／放棄：照論壇頁面上的連結送出（放棄要多問一次）
Future<bool> _runTaskLink(BuildContext context, api.TaskLink link, {String name = ''}) async {
  if (link.destructive) {
    final ok = await confirmDialog(
      context,
      title: tr('放棄任務${name.isEmpty ? '' : '「$name」'}？'),
      message: tr('目前的進度會清除。'),
      confirm: '放棄',
      danger: true,
    );
    if (!ok || !context.mounted) return false;
  }
  return submitAndToast(context, () => api.taskAction(link));
}

Widget _taskButton(BuildContext context, api.TaskLink l, VoidCallback onPressed) {
  if (l.destructive) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: errColor(context)),
      onPressed: onPressed,
      child: Text(l.label),
    );
  }
  return FilledButton(onPressed: onPressed, child: Text(l.label));
}

// ── 熱門任務 ──────────────────────────────────────────

class TaskPage extends StatelessWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('熱門任務'),
      actions: const [WebFallbackButton('home.php?mod=task')],
      tabs: [for (final l in api.TaskList.values) (tr(l.label), _ListTab(list: l))],
    );
  }
}

class _ListTab extends StatefulWidget {
  const _ListTab({required this.list});
  final api.TaskList list;

  @override
  State<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends State<_ListTab> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<api.TaskListPage>(
      key: ValueKey(_nonce),
      load: () => api.fetchTasks(widget.list),
      builder: (context, p, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          if (p.items.isEmpty)
            StateBox(empty: true, emptyText: p.message ?? (p.empty.isNotEmpty ? p.empty : tr('這裡沒有任務'))),
          for (final t in p.items)
            _TaskCard(
              task: t,
              onChanged: () => setState(() => _nonce++),
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onChanged});
  final api.TaskItem task;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push('/tools/task/${t.id}');
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: t.icon.isEmpty
                    ? Icon(LucideIcons.listChecks, color: faint(context))
                    : NetImage(url: t.icon, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  if (t.popularity.isNotEmpty) Pill(t.popularity, color: subtle(context), icon: LucideIcons.users),
                ]),
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(t.description,
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.45, color: subtle(context))),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (t.reward.isNotEmpty) Pill(t.reward, color: okColor(context), icon: LucideIcons.gift),
                  if (t.status.isNotEmpty) Text(t.status, style: TextStyle(fontSize: 12, color: faint(context))),
                ]),
                if (t.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final l in t.actions)
                      _taskButton(context, l, () async {
                        if (await _runTaskLink(context, l, name: t.name)) onChanged();
                      }),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── 任務詳情（每週發帖獎勵＝任務 25）─────────────────

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.id, this.title});
  final int id;
  final String? title;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.title ?? '任務')),
        actions: [WebFallbackButton('home.php?mod=task&do=view&id=${widget.id}')],
      ),
      body: Loader<api.TaskDetail>(
        key: ValueKey(_nonce),
        load: () => api.fetchTask(widget.id),
        builder: (context, t, reload) => _body(context, t),
      ),
    );
  }

  Widget _body(BuildContext context, api.TaskDetail t) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (t.message != null) NoteCard(t.message!),
        if (t.message == null) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (t.icon.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(width: 56, height: 56, child: NetImage(url: t.icon, fit: BoxFit.cover)),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if (t.period.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Pill(t.period, color: subtle(context), icon: LucideIcons.repeat),
                      ],
                    ]),
                  ),
                ]),
                if (t.progress != null) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Text(tr('完成度'), style: TextStyle(fontSize: 12.5, color: faint(context))),
                    const Spacer(),
                    Text('${t.progress}%', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: t.progress! / 100, minHeight: 8),
                  ),
                ],
                if (t.status.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(t.status, style: TextStyle(fontSize: 13, color: okColor(context), fontWeight: FontWeight.w600)),
                ],
                if (t.actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final l in t.actions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: _taskButton(context, l, () async {
                          if (await _runTaskLink(context, l, name: t.name)) setState(() => _nonce++);
                        }),
                      ),
                    ),
                ],
              ]),
            ),
          ),
          if (t.rows.isNotEmpty) ...[
            SectionTitle(tr('任務內容')),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < t.rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 116,
                        child: Text(t.rows[i].$1, style: TextStyle(fontSize: 12.5, color: faint(context))),
                      ),
                      Expanded(child: Text(t.rows[i].$2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
          if (t.description.isNotEmpty) ...[
            SectionTitle(tr('說明')),
            Text(t.description, style: TextStyle(fontSize: 14, height: 1.65, color: subtle(context))),
          ],
        ],
      ],
    );
  }
}

// ── 每月回帖獎勵 ──────────────────────────────────────

class ReplyRewardPage extends StatelessWidget {
  const ReplyRewardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('每月回帖獎勵'),
      actions: const [WebFallbackButton('reply_reward-reply_reward.html')],
      tabs: [
        (tr('本月進度'), const _RewardTab()),
        (tr('獎勵歷史'), const _HistoryTab()),
        (tr('達人榜'), const _RankTab()),
      ],
    );
  }
}

class _RewardTab extends StatefulWidget {
  const _RewardTab();

  @override
  State<_RewardTab> createState() => _RewardTabState();
}

class _RewardTabState extends State<_RewardTab> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<api.ReplyRewardPage>(
      key: ValueKey(_nonce),
      load: api.fetchReplyReward,
      builder: (context, p, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          if (p.boxes.isEmpty) StateBox(empty: true, emptyText: tr('目前沒有活動')),
          for (final b in p.boxes) _RewardCard(box: b, onClaimed: () => setState(() => _nonce++)),
          if (p.myInfo.isNotEmpty) ...[
            SectionTitle(tr('我的獎勵')),
            _Lines(p.myInfo),
          ],
          if (p.rules.isNotEmpty) ...[
            SectionTitle(tr('活動須知')),
            _Lines(p.rules),
          ],
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines(this.lines);
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('· $l', style: TextStyle(fontSize: 13, height: 1.5, color: subtle(context))),
              ),
          ]),
        ),
      );
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.box, required this.onClaimed});
  final api.ReplyRewardBox box;
  final VoidCallback onClaimed;

  @override
  Widget build(BuildContext context) {
    final b = box;
    final scheme = Theme.of(context).colorScheme;
    final done = b.percent >= 100;
    final color = done ? okColor(context) : scheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(
                value: (b.percent / 100).clamp(0.0, 1.0),
                strokeWidth: 7,
                color: color,
                backgroundColor: color.withValues(alpha: .15),
                strokeCap: StrokeCap.round,
              ),
              Center(child: Text('${b.percent}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color))),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(b.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                if (b.reward.isNotEmpty) Pill(b.reward, color: okColor(context), icon: LucideIcons.gift),
              ]),
              if (b.condition.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(b.condition, style: TextStyle(fontSize: 12.5, color: subtle(context))),
              ],
              if (b.progressText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(tr('進度：${b.progressText}'), style: TextStyle(fontSize: 12.5, color: subtle(context))),
              ],
              const SizedBox(height: 8),
              if (b.claim != null)
                FilledButton.icon(
                  icon: const Icon(LucideIcons.gift, size: 17),
                  label: Text(b.claim!.label),
                  onPressed: () async {
                    if (await _runTaskLink(context, b.claim!)) onClaimed();
                  },
                )
              else if (b.state.isNotEmpty)
                Pill(b.state, color: done ? okColor(context) : warnColor(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return Loader<List<(String, String, String)>>(
      load: api.fetchReplyRewardHistory,
      isEmpty: (l) => l.isEmpty,
      emptyText: '還沒有領過獎勵',
      builder: (context, l, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (type, credit, time) in l)
            ListTile(
              leading: Icon(LucideIcons.gift, color: okColor(context)),
              title: Text(type),
              subtitle: Text(time, style: TextStyle(fontSize: 12, color: faint(context))),
              trailing: Text(credit, style: TextStyle(fontWeight: FontWeight.w700, color: okColor(context))),
            ),
        ],
      ),
    );
  }
}

class _RankTab extends StatelessWidget {
  const _RankTab();

  @override
  Widget build(BuildContext context) {
    return Loader<List<(int, String, int?, String, String)>>(
      load: api.fetchReplyRewardRank,
      isEmpty: (l) => l.isEmpty,
      emptyText: '還沒有排名',
      builder: (context, l, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (rank, name, uid, avatar, detail) in l)
            ListTile(
              leading: SizedBox(
                width: 76,
                child: Row(children: [
                  SizedBox(width: 30, child: RankNumber('$rank')),
                  const SizedBox(width: 6),
                  Avatar(avatar, size: 36),
                ]),
              ),
              title: Text(name),
              subtitle: detail.isEmpty ? null : Text(detail, style: TextStyle(fontSize: 12, color: faint(context))),
              onTap: uid == null ? null : () => context.push('/u/$uid'),
            ),
        ],
      ),
    );
  }
}
