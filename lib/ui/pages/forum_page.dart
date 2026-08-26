import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/login_required.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key, required this.fid});
  final int fid;

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  ForumData? _data;
  bool _loading = true;
  String? _err;
  int _page = 1;
  ForumQuery _q = const ForumQuery();
  final _scroll = ScrollController();

  /// 論壇自己的四個分頁 + 網頁版才有的「熱帖」
  static const _tabs = <({String value, String label})>[
    (value: '', label: '全部'),
    (value: 'lastpost', label: '最新'),
    (value: 'heat', label: '熱門'),
    (value: 'hot', label: '熱帖'),
    (value: 'digest', label: '精華'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchForum(widget.fid, page: _page, query: _q);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  void _apply(ForumQuery q) {
    setState(() {
      _q = q;
      _page = 1;
    });
    _load();
  }

  Future<void> _pickSpecial() async {
    final v = await _sheet<String>(
      title: tr('主題類別'),
      options: [
        for (final o in forumSpecialOptions) (value: o.value, label: tr(o.label))
      ],
      current: _q.special,
    );
    if (v != null) _apply(_q.copyWith(special: v, typeid: 0));
  }

  Future<void> _pickType() async {
    final d = _data;
    if (d == null || d.types.isEmpty) return;
    final v = await _sheet<int>(
      title: tr('主題分類'),
      options: [
        (value: 0, label: tr('不分類')),
        for (final t in d.types)
          (value: t.typeid, label: t.count.isEmpty ? t.name : '${t.name} ${t.count}'),
      ],
      current: _q.typeid,
    );
    if (v != null) _apply(_q.copyWith(typeid: v, special: ''));
  }

  /// 排序與時間放同一張表，跟網頁版的「更多」一致
  Future<void> _openMore() async {
    var q = _q;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('排序'),
                    style: TextStyle(fontSize: 12, color: faint(c))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in forumOrderOptions)
                      ChoiceChip(
                        label: Text(tr(o.label)),
                        selected: q.orderby == o.value,
                        onSelected: (_) =>
                            setSheet(() => q = q.copyWith(orderby: o.value)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(tr('時間'),
                    style: TextStyle(fontSize: 12, color: faint(c))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in forumDateOptions)
                      ChoiceChip(
                        label: Text(tr(o.label)),
                        selected: q.dateline == o.value,
                        onSelected: (_) =>
                            setSheet(() => q = q.copyWith(dateline: o.value)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(() =>
                          q = q.copyWith(orderby: '', dateline: 0)),
                      child: Text(tr('清除')),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(tr('套用')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (q.orderby != _q.orderby || q.dateline != _q.dateline) _apply(q);
  }

  Future<T?> _sheet<T>({
    required String title,
    required List<({T value, String label})> options,
    required T current,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title,
                    style: TextStyle(fontSize: 12, color: faint(c))),
              ),
              for (final o in options)
                ListTile(
                  title: Text(o.label, style: const TextStyle(fontSize: 15)),
                  trailing: o.value == current
                      ? Icon(LucideIcons.check,
                          size: 20, color: Theme.of(c).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(c, o.value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.name ?? tr('板塊')),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.search),
            tooltip: tr('在本版搜尋'),
            onPressed: () => context.push(Uri(
              path: '/f/${widget.fid}/search',
              queryParameters: {'name': d?.name ?? ''},
            ).toString()),
          ),
        ],
      ),
      floatingActionButton: context.watch<SessionStore>().loggedIn
          ? FloatingActionButton(
              onPressed: () => context.push('/f/${widget.fid}/post'),
              tooltip: tr('發表新主題'),
              child: const Icon(LucideIcons.squarePen),
            )
          : null,
      bottomNavigationBar: d == null
          ? null
          : StickyPager(
              pager: d.pager,
              onGo: (p) {
                setState(() => _page = p);
                _load();
              },
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            if (d != null && d.meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                child: Row(
                  children: [
                    for (final m in d.meta)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(m,
                            style: TextStyle(fontSize: 12, color: faint(context))),
                      ),
                  ],
                ),
              ),
            if (d != null && d.subforums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final sub in d.subforums)
                      ActionChip(
                        avatar: const Icon(LucideIcons.folder, size: 15),
                        label: Text(sub.name, style: const TextStyle(fontSize: 13)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => context.push('/f/${sub.fid}'),
                      ),
                  ],
                ),
              ),
            _filterBar(d),
            if (d?.requiresLogin ?? false)
              LoginRequired(message: d?.message)
            else
              ?StateBox.maybe(
                loading: _loading,
                error: _err,
                empty: !_loading && _err == null && (d?.list.isEmpty ?? false),
                emptyText: d?.message ?? tr('這個板塊沒有主題'),
                onRetry: _load,
              ),
            if (d != null && d.list.isNotEmpty) ThreadListCard(list: d.list),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(ForumData? d) {
    final accent = Theme.of(context).colorScheme.primary;
    final specialLabel = forumSpecialOptions
        .firstWhere((o) => o.value == _q.special,
            orElse: () => forumSpecialOptions.first)
        .label;
    final typeName = _q.typeid == 0
        ? null
        : d?.types
            .where((t) => t.typeid == _q.typeid)
            .map((t) => t.name)
            .firstOrNull;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        children: [
          _dropdown(
            label: typeName ?? tr(specialLabel),
            active: _q.special.isNotEmpty || _q.typeid > 0,
            onTap: _pickSpecial,
          ),
          if (d != null && d.types.isNotEmpty)
            _dropdown(
              label: tr('分類'),
              active: _q.typeid > 0,
              onTap: _pickType,
            ),
          for (final t in _tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tr(t.label)),
                selected: _q.tab == t.value,
                onSelected: (_) => _apply(_q.copyWith(tab: t.value)),
              ),
            ),
          _dropdown(
            label: tr('更多'),
            active: _q.hasExtra,
            onTap: _openMore,
            icon: LucideIcons.slidersHorizontal,
            accent: accent,
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData icon = LucideIcons.chevronDown,
    Color? accent,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: Icon(icon,
              size: 16,
              color: active ? (accent ?? Theme.of(context).colorScheme.primary) : null),
          label: Text(label),
          side: active
              ? BorderSide(color: Theme.of(context).colorScheme.primary)
              : null,
          onPressed: onTap,
        ),
      );
}
