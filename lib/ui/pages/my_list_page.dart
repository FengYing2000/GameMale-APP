import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';
import '../widgets/toast.dart';
import 'package:go_router/go_router.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({super.key, required this.type});
  final String type;

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  static const _titles = {
    'favorite': '我的收藏',
    'thread': '我的主題',
    'reply': '我的回覆',
  };

  ListPage? _data;
  List<SubForum>? _forums;
  String _postType = 'thread';
  bool _favForums = false;   // 收藏頁的「版塊」分頁
  bool _loading = true;
  String? _err;
  int _page = 1;

  /// 版塊篩選（我的主題／回覆才有），0 = 全部
  int _filterFid = 0;
  List<ForumGroup> _forumTree = const [];

  @override
  void initState() {
    super.initState();
    if (widget.type == 'reply') _postType = 'reply';
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<SessionStore>().uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _err = tr('尚未登入');
      });
      return;
    }

    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      if (widget.type == 'favorite' && _favForums) {
        final f = await api.fetchFavoriteForums(uid, page: _page);
        if (mounted) setState(() => _forums = f);
      } else {
        final d = widget.type == 'favorite'
            ? await api.fetchFavorites(uid, page: _page)
            : await api.fetchGuideMine(
                type: _postType, page: _page, fid: _filterFid);
        if (mounted) setState(() => _data = d);
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadForumTree() async {
    if (_forumTree.isNotEmpty) return;
    try {
      final idx = await api.fetchIndex();
      if (mounted) setState(() => _forumTree = idx.groups);
    } on DiscuzException {
      // 抓不到就不給篩選，其他照常
    }
  }

  Future<void> _pickForum() async {
    await _loadForumTree();
    if (!mounted || _forumTree.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.of(c).size.height * .7,
        child: ListView(
          children: [
            ListTile(
              title: Text(tr('全部版塊')),
              trailing: _filterFid == 0
                  ? Icon(LucideIcons.check, color: Theme.of(c).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(c, 0),
            ),
            for (final g in _forumTree) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(g.name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: faint(c))),
              ),
              for (final f in g.forums)
                ListTile(
                  dense: true,
                  title: Text(f.name, style: const TextStyle(fontSize: 14)),
                  trailing: _filterFid == f.fid
                      ? Icon(LucideIcons.check,
                          size: 20, color: Theme.of(c).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(c, f.fid),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterFid = picked;
      _page = 1;
    });
    _load();
  }

  /// 「我的回覆」點了直接跳到自己那一樓所在的頁
  Future<void> _openReply(ThreadItem t) async {
    if (t.myPid == null) {
      context.push('/t/${t.tid}');
      return;
    }
    try {
      final page = await api.resolvePostPage(t.tid, t.myPid!);
      if (!mounted) return;
      context.push('/t/${t.tid}?page=$page&pid=${t.myPid}');
    } on DiscuzException {
      if (mounted) context.push('/t/${t.tid}');
    }
  }

  Future<void> _removeForum(SubForum f) async {
    final favid = f.favid;
    if (favid == null) return;
    try {
      final r = await api.unfavorite(favid);
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) {
        setState(() => _forums = _forums!.where((x) => x.favid != favid).toList());
      }
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('取消收藏失敗：${e.message}'));
    }
  }

  Future<void> _remove(ThreadItem t) async {
    final favid = t.favid;
    if (favid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('取消收藏')),
        content: Text(t.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('確定'))),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final r = await api.unfavorite(favid);
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) {
        setState(() {
          _data = ListPage(
            list: _data!.list.where((x) => x.favid != favid).toList(),
            pager: _data!.pager,
          );
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('取消收藏失敗：${e.message}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final isFav = widget.type == 'favorite';

    return Scaffold(
      bottomNavigationBar: (_favForums || d == null || d.list.isEmpty)
          ? null
          : StickyPager(
              pager: d.pager,
              onGo: (p) {
                setState(() => _page = p);
                _load();
              },
            ),
      appBar: AppBar(title: Text(tr(_titles[widget.type] ?? '列表'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (!isFav)
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  children: [
                    for (final t in api.myPostTypes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(tr(t.name)),
                          selected: _postType == t.type,
                          onSelected: (_) {
                            setState(() {
                              _postType = t.type;
                              _page = 1;
                            });
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            if (!isFav)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickForum,
                      icon: const Icon(LucideIcons.filter, size: 16),
                      label: Text(
                        _filterFid == 0
                            ? tr('全部版塊')
                            : (_forumTree
                                    .expand((g) => g.forums)
                                    .where((f) => f.fid == _filterFid)
                                    .map((f) => f.name)
                                    .firstOrNull ??
                                tr('已篩選')),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (_filterFid != 0)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _filterFid = 0;
                            _page = 1;
                          });
                          _load();
                        },
                        child: Text(tr('清除')),
                      ),
                  ],
                ),
              ),
            if (isFav)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('帖子'))),
                    ButtonSegment(value: true, label: Text(tr('版塊'))),
                  ],
                  selected: {_favForums},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    setState(() {
                      _favForums = v.first;
                      _page = 1;
                    });
                    _load();
                  },
                ),
              ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading &&
                  _err == null &&
                  (isFav && _favForums
                      ? (_forums?.isEmpty ?? false)
                      : (d?.list.isEmpty ?? false)),
              emptyText: tr('這裡還是空的'),
              onRetry: _load,
            ),
            if (isFav && _favForums && (_forums?.isNotEmpty ?? false))
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _forums!.length; i++) ...[
                      ListTile(
                        leading: const Icon(LucideIcons.folder),
                        title: Text(_forums![i].name),
                        subtitle: _forums![i].favTime.isEmpty
                            ? null
                            : Text(_forums![i].favTime,
                                style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(LucideIcons.star, size: 20),
                          tooltip: tr('取消收藏'),
                          onPressed: () => _removeForum(_forums![i]),
                        ),
                        onTap: () => context.push('/f/${_forums![i].fid}'),
                      ),
                      if (i != _forums!.length - 1)
                        const Divider(indent: 56, endIndent: 14),
                    ],
                  ],
                ),
              ),
            if (!(isFav && _favForums) && d != null && d.list.isNotEmpty)
              if (_postType == 'reply' && !isFav)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < d.list.length; i++) ...[
                        _ReplyTile(
                            item: d.list[i],
                            onTap: () => _openReply(d.list[i])),
                        if (i != d.list.length - 1)
                          const Divider(height: 1, indent: 14, endIndent: 14),
                      ],
                    ],
                  ),
                )
              else
                ThreadListCard(list: d.list, onRemove: isFav ? _remove : null),
          ],
        ),
      ),
    );
  }
}

/// 我的回覆：上面是帖子，下面是我當時回了什麼
class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.item, required this.onTap});
  final ThreadItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600)),
            if (item.myReply.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(item.myReply,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, height: 1.5, color: subtle(context))),
              ),
            ],
            const SizedBox(height: 7),
            Row(
              children: [
                if (item.forumName.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(item.forumName,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    [
                      if (item.author.isNotEmpty) item.author,
                      if (item.date.isNotEmpty) item.date,
                      '${item.replies} / ${item.views}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: faint(context)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
