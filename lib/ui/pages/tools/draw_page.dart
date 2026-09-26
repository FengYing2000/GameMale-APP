import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/draw.dart' as api;
import 'package:gm_api/http.dart' show Api;
import 'package:gm_api/models.dart';
import '../../../i18n/ui.dart';
import '../../../store/session.dart';
import '../../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/external_link.dart';
import '../../widgets/keyboard_tap_outside.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/state_box.dart';
import '../../widgets/toast.dart';

/// 你畫我猜（viewui_draw）：大廳、我的紀錄、排行榜；點畫作進猜題頁
class DrawPage extends StatelessWidget {
  const DrawPage({super.key});

  static const _drawPath = 'plugin.php?id=viewui_draw&mod=list&ac=draw';

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('你畫我猜'),
      actions: [
        // 畫布頁還沒原生化：先開論壇原本的畫布
        IconButton(
          tooltip: tr('我來畫'),
          icon: const Icon(LucideIcons.brush, size: 20),
          onPressed: () => openInApp(context, Api.desktopFullUrl(_drawPath), title: tr('我來畫')),
        ),
      ],
      tabs: [
        (tr('大廳'), const _LobbyTab()),
        (tr('我的紀錄'), const _LogTab()),
        (tr('排行榜'), const _RankTab()),
      ],
    );
  }
}

class _LobbyTab extends StatefulWidget {
  const _LobbyTab();

  @override
  State<_LobbyTab> createState() => _LobbyTabState();
}

class _LobbyTabState extends State<_LobbyTab> with AutomaticKeepAliveClientMixin {
  int _status = 0;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      CategoryBar<int>(
        items: [(0, tr('全部'), null), (1, tr('進行中'), null), (2, tr('已完結'), null)],
        selected: _status,
        onSelect: (v) => setState(() {
          _status = v;
          _page = 1;
        }),
      ),
      Expanded(
        child: Loader<api.DrawLobby>(
          key: ValueKey('$_status-$_page'),
          load: () => api.fetchDrawLobby(status: _status, page: _page),
          builder: (context, l, reload) => ItemGrid(
            maxWidth: 200,
            aspect: .78,
            header: [if (l.items.isEmpty) StateBox(empty: true, emptyText: l.message ?? tr('目前沒有畫作'))],
            footer: [?pagerOf(l.pager, (n) => setState(() => _page = n))],
            children: [
              for (final d in l.items)
                ItemCard(
                  image: d.image,
                  title: d.topic.isEmpty ? tr('畫作 #${d.id}') : d.topic,
                  subtitle: d.participants,
                  imagePadding: 4,
                  corner: Pill(tr(d.ongoing ? '進行中' : '已完結'), color: d.ongoing ? okColor(context) : faint(context)),
                  badge: d.answer.isNotEmpty
                      ? Pill(d.answer, color: subtle(context), icon: LucideIcons.lightbulb)
                      : (d.lastSay.isNotEmpty ? Pill(d.lastSay, icon: LucideIcons.messageCircle) : null),
                  onTap: () async {
                    await context.push('/tools/draw/${d.id}');
                    if (mounted) await reload();
                  },
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── 猜題頁 ────────────────────────────────────────────

class DrawDetailPage extends StatefulWidget {
  const DrawDetailPage({super.key, required this.id});
  final int id;

  @override
  State<DrawDetailPage> createState() => _DrawDetailPageState();
}

class _DrawDetailPageState extends State<DrawDetailPage> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('你畫我猜'))),
      body: Loader<api.DrawDetail>(
        key: ValueKey(_nonce),
        load: () => api.fetchDrawDetail(widget.id),
        builder: (context, d, reload) => Column(children: [
          Expanded(child: _DetailBody(detail: d)),
          if (d.message == null) _Composer(detail: d, onSent: () => setState(() => _nonce++)),
        ]),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});
  final api.DrawDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final scheme = Theme.of(context).colorScheme;
    final chats = [for (final c in d.comments) if (!c.date && !c.system) c];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        if (d.message != null) NoteCard(d.message!),
        if (d.image.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(aspectRatio: 4 / 3, child: NetImage(url: d.image, fit: BoxFit.contain)),
          ),
        const SizedBox(height: 12),
        Text(d.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (d.tip.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(LucideIcons.lightbulb, size: 15, color: warnColor(context)),
            const SizedBox(width: 6),
            Expanded(child: Text(d.tip, style: TextStyle(fontSize: 13.5, color: warnColor(context), fontWeight: FontWeight.w600))),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (d.answered) Pill(tr('已有人猜中'), color: okColor(context), icon: LucideIcons.circleCheck),
          Pill(tr('這幅還能猜 ${d.leftThis} 次'), color: scheme.primary),
          Pill(tr('今天還能猜 ${d.leftToday} 次'), color: subtle(context)),
          Pill(tr('${chats.length} 則'), color: subtle(context), icon: LucideIcons.messageCircle),
        ]),
        const SizedBox(height: 14),
        if (d.comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text(tr('還沒有人猜，搶頭香吧'), style: TextStyle(color: faint(context)))),
          ),
        for (final c in d.comments) _CommentRow(comment: c),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final api.DrawComment comment;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    if (c.date || c.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(c.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: faint(context))),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final tint = c.correct == true ? okColor(context) : (c.guess ? scheme.primary : subtle(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(c.avatar, size: 34, onTap: c.uid == null ? null : () => context.push('/u/${c.uid}')),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: c.user),
                TextSpan(text: c.guess ? tr('  猜') : tr('  說'), style: TextStyle(color: tint)),
              ]),
              style: TextStyle(fontSize: 12, color: faint(context)),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: c.guess ? .1 : .07),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                  topLeft: Radius.circular(4),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(c.text, style: const TextStyle(fontSize: 14, height: 1.4))),
                if (c.correct != null) ...[
                  const SizedBox(width: 6),
                  Icon(c.correct! ? LucideIcons.circleCheck : LucideIcons.circleX,
                      size: 16, color: c.correct! ? okColor(context) : errColor(context)),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.detail, required this.onSent});
  final api.DrawDetail detail;
  final VoidCallback onSent;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _guess = true;
  bool _busy = false;

  /// 不能猜的原因（null＝可以猜）
  String? _noGuess(BuildContext context) {
    final d = widget.detail;
    final me = context.read<SessionStore>().uid;
    if (d.answered) return tr('已經有人猜中，只能吐槽');
    if (me != null && d.authorUid == me) return tr('自己的畫不能猜，只能吐槽');
    if (d.leftThis <= 0) return tr('這幅畫的次數用完了，只能吐槽');
    if (d.leftToday <= 0) return tr('今天的競猜次數用完了，只能吐槽');
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(bool guess) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    api.DrawGuessResult r;
    try {
      r = await api.sendDrawGuess(widget.detail, text, guess: guess);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message, kind: ToastKind.warn);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (!r.ok) {
      toast(context, r.message, kind: ToastKind.warn);
      return;
    }
    _ctrl.clear();
    if (guess && r.correct) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(LucideIcons.partyPopper, size: 40, color: okColor(c)),
          title: Text(tr('猜中了！')),
          content: Text(
            [
              if (r.answer.isNotEmpty) tr('答案是「${r.answer}」'),
              if (r.reward.isNotEmpty) tr('獲得 ${r.reward}'),
            ].join('\n'),
            textAlign: TextAlign.center,
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('好')))],
        ),
      );
    } else if (guess) {
      toast(context, r.leftThis == null ? tr('沒猜中') : tr('沒猜中，這幅還能猜 ${r.leftThis} 次'), kind: ToastKind.warn);
    } else {
      toast(context, tr('已送出'), kind: ToastKind.ok);
    }
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    final block = _noGuess(context);
    final guess = _guess && block == null;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: true, label: Text(tr('猜答案')), enabled: block == null),
                  ButtonSegment(value: false, label: Text(tr('吐槽'))),
                ],
                selected: {guess},
                onSelectionChanged: (s) => setState(() => _guess = s.first),
              ),
              const SizedBox(width: 8),
              if (block != null)
                Expanded(
                  child: Text(block, maxLines: 2, style: TextStyle(fontSize: 11.5, color: faint(context))),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onTapOutside: keyboardTapOutside(_focus),
                  textInputAction: TextInputAction.send,
                  onSubmitted: _busy ? null : (_) => _send(guess),
                  maxLength: guess ? 20 : 100,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: guess ? tr('輸入你猜的答案') : tr('說點什麼'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: guess ? scheme.primary : scheme.secondary),
                onPressed: _busy ? null : () => _send(guess),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(guess ? LucideIcons.send : LucideIcons.messageCircle, size: 19),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── 我的紀錄 ──────────────────────────────────────────

class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> with AutomaticKeepAliveClientMixin {
  bool _created = false;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      CategoryBar<bool>(
        items: [(false, tr('我參與的'), null), (true, tr('我畫的'), null)],
        selected: _created,
        onSelect: (v) => setState(() {
          _created = v;
          _page = 1;
        }),
      ),
      Expanded(
        child: Loader<api.DrawLog>(
          key: ValueKey('$_created-$_page'),
          load: () => api.fetchDrawLog(created: _created, page: _page),
          builder: (context, l, reload) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              if (l.stats.isNotEmpty)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      for (final (n, label) in l.stats)
                        Expanded(
                          child: Column(children: [
                            Text(n, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(label, style: TextStyle(fontSize: 11.5, color: faint(context))),
                          ]),
                        ),
                    ]),
                  ),
                ),
              if (l.today.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [for (final t in l.today) Pill(t, color: subtle(context))]),
                ),
              if (l.rows.isEmpty) StateBox(empty: true, emptyText: tr('還沒有紀錄')),
              const SizedBox(height: 8),
              for (final r in l.rows)
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 52,
                      height: 42,
                      color: Colors.white,
                      child: r.image.isEmpty ? null : NetImage(url: r.image, fit: BoxFit.contain),
                    ),
                  ),
                  title: Text([r.topic, r.type].where((e) => e.isNotEmpty).join(' · ')),
                  subtitle: Text([r.content, r.time].where((e) => e.isNotEmpty).join('\n'),
                      style: TextStyle(fontSize: 12.5, color: subtle(context))),
                  isThreeLine: r.content.isNotEmpty && r.time.isNotEmpty,
                  trailing: r.correct == null
                      ? null
                      : Icon(r.correct! ? LucideIcons.circleCheck : LucideIcons.circleX,
                          color: r.correct! ? okColor(context) : errColor(context)),
                  onTap: r.drawId == null ? null : () => context.push('/tools/draw/${r.drawId}'),
                ),
              ?pagerOf(l.pager, (n) => setState(() => _page = n)),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── 排行榜 ────────────────────────────────────────────

class _RankTab extends StatefulWidget {
  const _RankTab();

  @override
  State<_RankTab> createState() => _RankTabState();
}

class _RankTabState extends State<_RankTab> with AutomaticKeepAliveClientMixin {
  bool _draw = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      CategoryBar<bool>(
        items: [(false, tr('競猜榜'), null), (true, tr('繪畫榜'), null)],
        selected: _draw,
        onSelect: (v) => setState(() => _draw = v),
      ),
      Expanded(
        child: Loader<(String, List<api.DrawRankRow>)>(
          key: ValueKey(_draw),
          load: () => api.fetchDrawRank(draw: _draw),
          builder: (context, r, reload) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              if (r.$1.isNotEmpty) NoteCard(r.$1),
              if (r.$2.isEmpty) StateBox(empty: true, emptyText: tr('還沒有排名')),
              const SizedBox(height: 6),
              for (final row in r.$2)
                ListTile(
                  leading: SizedBox(
                    width: 76,
                    child: Row(children: [
                      SizedBox(width: 30, child: RankNumber(row.rank)),
                      const SizedBox(width: 6),
                      Avatar(row.avatar, size: 36),
                    ]),
                  ),
                  title: Text(row.user),
                  subtitle: row.detail.isEmpty ? null : Text(row.detail, style: TextStyle(fontSize: 12, color: faint(context))),
                  onTap: row.uid == null ? null : () => context.push('/u/${row.uid}'),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}
