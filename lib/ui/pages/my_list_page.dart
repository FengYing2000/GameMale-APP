import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
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
  bool _favForums = false;   // 收藏頁的「版塊」分頁
  bool _loading = true;
  String? _err;
  int _page = 1;

  @override
  void initState() {
    super.initState();
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
        final d = switch (widget.type) {
          'favorite' => await api.fetchFavorites(uid, page: _page),
          'reply' => await api.fetchMyReplies(uid, page: _page),
          _ => await api.fetchMyThreads(uid, page: _page),
        };
        if (mounted) setState(() => _data = d);
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
      appBar: AppBar(title: Text(tr(_titles[widget.type] ?? '列表'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
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
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(_forums![i].name),
                        subtitle: _forums![i].favTime.isEmpty
                            ? null
                            : Text(_forums![i].favTime,
                                style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.star, size: 20),
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
              ThreadListCard(list: d.list, onRemove: isFav ? _remove : null),
            if (!(isFav && _favForums) && d != null)
              PagerBar(
                pager: d.pager,
                onGo: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }
}
