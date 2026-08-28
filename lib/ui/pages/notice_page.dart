import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/state_box.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  String _view = 'mypost';
  String _type = '';
  NoticeResult? _data;
  bool _loading = true;
  String? _err;

  /// 各類提醒的未讀數，用來高亮「是哪一類有新的」
  Map<String, int> _unread = const {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 先問頁首各類未讀數，有新的就直接跳到那一類，並在分頁上標出來
  Future<void> _boot() async {
    try {
      final b = await api.fetchBadges();
      if (!mounted) return;
      setState(() => _unread = b.views);
      // 依 noticeViews 的順序挑第一個有未讀的分類（例如系統提醒）
      for (final v in api.noticeViews) {
        if ((b.views[v.view] ?? 0) > 0) {
          _view = v.view;
          break;
        }
      }
    } on DiscuzException {
      // 抓不到就用預設分類
    }
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchNotice(view: _view, type: _type);
      if (mounted) {
        setState(() {
          _data = d;
          // 這一類看過了，取消它的高亮
          if (_unread.containsKey(_view)) {
            _unread = {..._unread}..remove(_view);
          }
        });
        // 看過提醒＝當作都讀了，先熄鈴鐺（下次首頁重抓會依伺服器校正）
        context.read<SessionStore>().markNoticesSeen();
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickView(String view) {
    setState(() {
      _view = view;
      _type = '';
    });
    _load();
  }

  void _pickType(String type) {
    setState(() => _type = type);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final subTabs = api.noticeTypes[_view];

    return Scaffold(
      appBar: AppBar(title: Text(tr('通知'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _ChipRow(
              items: [for (final v in api.noticeViews) (v.view, v.name)],
              selected: _view,
              onPick: _pickView,
              badges: _unread,
            ),
            if (subTabs != null)
              _ChipRow(
                items: [for (final t in subTabs) (t.type, t.name)],
                selected: _type,
                onPick: _pickType,
                small: true,
              ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.items.isEmpty ?? false),
              emptyText: d?.message ?? tr('目前沒有新通知'),
              onRetry: _load,
            ),
            if (d != null && d.items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < d.items.length; i++) ...[
                      _NoticeRow(item: d.items[i]),
                      if (i != d.items.length - 1)
                        const Divider(indent: 60, endIndent: 14),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.items,
    required this.selected,
    required this.onPick,
    this.small = false,
    this.badges = const {},
  });

  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onPick;
  final bool small;

  /// 分類 → 未讀數，有數字的分類會加上紅色數量標記並描邊
  final Map<String, int> badges;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: small ? 42 : 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(12, small ? 4 : 10, 12, 2),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(builder: (context) {
                final n = badges[it.$1] ?? 0;
                return ChoiceChip(
                  avatar: n > 0
                      ? Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF1744),
                            borderRadius: BorderRadius.all(Radius.circular(9)),
                          ),
                          child: Text(n > 99 ? '99+' : '$n',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        )
                      : null,
                  label: Text(it.$2,
                      style: TextStyle(fontSize: small ? 12.5 : 14)),
                  selected: selected == it.$1,
                  visualDensity: small ? VisualDensity.compact : null,
                  side: n > 0 ? BorderSide(color: accent, width: 1.4) : null,
                  onSelected: (_) => onPick(it.$1),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.item});
  final NoticeItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.tid == null ? null : () => context.push('/t/${item.tid}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(item.avatar,
                size: 34,
                onTap: item.uid == null ? null : () => context.push('/u/${item.uid}')),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.text, style: const TextStyle(fontSize: 14, height: 1.55)),
                  const SizedBox(height: 4),
                  Text(item.time,
                      style: TextStyle(fontSize: 11.5, color: faint(context))),
                ],
              ),
            ),
            if (item.tid != null)
              Icon(LucideIcons.chevronRight, size: 18, color: faint(context)),
          ],
        ),
      ),
    );
  }
}
