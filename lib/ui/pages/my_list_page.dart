import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';
import '../widgets/toast.dart';

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
        _err = '尚未登入';
      });
      return;
    }

    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = switch (widget.type) {
        'favorite' => await api.fetchFavorites(uid, page: _page),
        'reply' => await api.fetchMyReplies(uid, page: _page),
        _ => await api.fetchMyThreads(uid, page: _page),
      };
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(ThreadItem t) async {
    final favid = t.favid;
    if (favid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text(t.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('確定')),
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
      if (mounted) toast(context, '取消收藏失敗：${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final isFav = widget.type == 'favorite';

    return Scaffold(
      appBar: AppBar(title: Text(_titles[widget.type] ?? '列表')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.list.isEmpty ?? false),
              emptyText: '這裡還是空的',
              onRetry: _load,
            ),
            if (d != null && d.list.isNotEmpty)
              ThreadListCard(list: d.list, onRemove: isFav ? _remove : null),
            if (d != null)
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
