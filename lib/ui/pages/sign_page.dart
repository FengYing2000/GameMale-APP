import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_body.dart';
import '../widgets/require_login.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class SignPage extends StatefulWidget {
  const SignPage({super.key});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  SignResult? _data;
  bool _loading = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchSignPage();
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sign() async {
    if (!await requireLogin(context, action: tr('簽到'))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.doSign();
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('簽到失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 獎勵規則／簽到等級／道具擴展，論壇拆成三頁，這裡放同一張表裡切
  Future<void> _showRules() async {
    var op = signRulePages.first.op;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SizedBox(
          height: MediaQuery.of(c).size.height * .8,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final p in signRulePages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(tr(p.name)),
                          selected: op == p.op,
                          onSelected: (_) => setSheet(() => op = p.op),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: op == 'magics'
                    ? const _MagicsView()
                    : _RulesView(key: ValueKey(op), op: op),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final session = context.watch<SessionStore>();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('每日簽到')),
        actions: [
          IconButton(
            tooltip: tr('獎勵規則'),
            icon: const Icon(LucideIcons.circleHelp),
            onPressed: _showRules,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              _card(d, session),
              // 解不出結構化欄位時才退回原始 HTML
              if (d.stats.isEmpty && d.html.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: PostBody(
                      d.html,
                      textStyle: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(SignResult d, SessionStore session) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: .22),
                  scheme.primary.withValues(alpha: .06),
                ],
              ),
            ),
            child: Column(
              children: [
                Avatar(session.avatar, size: 62),
                const SizedBox(height: 10),
                Text(
                  session.name.isEmpty ? tr('尚未登入') : session.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (d.level.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(d.level,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                  ),
                ],
              ],
            ),
          ),
          if (d.stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  for (final s in d.stats)
                    Expanded(
                      child: Column(
                        children: [
                          Text(s.value,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(s.label,
                              style: TextStyle(
                                  fontSize: 11.5, color: faint(context))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: d.signed
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(LucideIcons.circleCheckBig, size: 18),
                      label: Text(tr('今天已經簽到了')),
                    )
                  : FilledButton.icon(
                      onPressed: _busy ? null : _sign,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.calendarCheck, size: 19),
                      label: Text(_busy ? tr('簽到中…') : tr('立即簽到')),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesView extends StatefulWidget {
  const _RulesView({super.key, required this.op});
  final String op;

  @override
  State<_RulesView> createState() => _RulesViewState();
}

class _RulesViewState extends State<_RulesView> {
  SignRules? _rules;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final r = await api.fetchSignRules(widget.op);
      if (mounted) setState(() => _rules = r);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _rules;
    if (_err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_err!, style: TextStyle(fontSize: 13, color: faint(context))),
            TextButton(onPressed: _load, child: Text(tr('重試'))),
          ],
        ),
      );
    }
    if (r == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (r.intro.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(r.intro,
                style: const TextStyle(fontSize: 14, height: 1.6)),
          ),
        if (r.text.isNotEmpty)
          Text(r.text, style: TextStyle(fontSize: 13.5, height: 1.8, color: subtle(context))),
        for (final t in r.tables) ...[
          if (t.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: Text(t.title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: faint(context))),
            ),
          for (var i = 0; i < t.rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  for (var j = 0; j < t.rows[i].length; j++)
                    Expanded(
                      flex: j == 0 ? 3 : 4,
                      child: Text(
                        t.rows[i][j],
                        style: TextStyle(
                          fontSize: 13,
                          // 第一列是表頭
                          fontWeight: i == 0 ? FontWeight.w600 : null,
                          color: i == 0 ? null : subtle(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// 道具擴展。論壇這頁不是說明文字，是可以直接補簽或買補簽卡的
class _MagicsView extends StatefulWidget {
  const _MagicsView();

  @override
  State<_MagicsView> createState() => _MagicsViewState();
}

class _MagicsViewState extends State<_MagicsView> {
  List<SignMagic>? _items;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final m = await api.fetchSignMagics();
      if (mounted) setState(() => _items = m);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  Future<void> _act(String url, String what) async {
    if (!await requireLogin(context, action: what)) return;
    if (!mounted) return;
    try {
      final r = await api.confirmAndSubmit(url, what);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '$what${tr('失敗：')}${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_err != null) {
      return Center(
        child: TextButton(onPressed: _load, child: Text(tr('重試'))),
      );
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (items.isEmpty) {
      return Center(
        child: Text(tr('目前沒有可用的道具'),
            style: TextStyle(fontSize: 13, color: faint(context))),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final m in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (m.icon.isNotEmpty) ...[
                        SmartImage(src: m.icon, height: 32),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(m.name,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (m.desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(m.desc,
                        style: TextStyle(
                            fontSize: 13, height: 1.6, color: subtle(context))),
                  ],
                  if (m.detail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(m.detail,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.7, color: faint(context))),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (m.useUrl.isNotEmpty)
                        FilledButton(
                          onPressed: () => _act(m.useUrl, tr('補簽')),
                          child: Text(tr('補簽')),
                        ),
                      if (m.buyUrl.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () => _act(m.buyUrl, tr('購買')),
                          child: Text(tr('購買補簽卡')),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
