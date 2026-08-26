import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';
import '../widgets/toast.dart';

/// 淘帖（收藏專輯）列表：推薦／所有／我的
class CollectionListPage extends StatefulWidget {
  const CollectionListPage({super.key});

  @override
  State<CollectionListPage> createState() => _CollectionListPageState();
}

class _CollectionListPageState extends State<CollectionListPage> {
  String _op = '';
  List<CollectionItem> _items = const [];
  PageInfo _pager = const PageInfo();
  bool _loading = true;
  String? _err;
  int _page = 1;
  final _scroll = ScrollController();

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

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _err = null;
      if (page != null) _page = page;
    });
    try {
      final r = await api.fetchCollectionIndex(op: _op, page: _page);
      if (mounted) {
        setState(() {
          _items = r.items;
          _pager = r.pager;
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('淘帖'))),
      bottomNavigationBar: _items.isEmpty
          ? null
          : StickyPager(pager: _pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                children: [
                  for (final t in collectionTabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(t.name)),
                        selected: _op == t.op,
                        onSelected: (_) {
                          setState(() {
                            _op = t.op;
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && _items.isEmpty,
              emptyText: tr('這裡還沒有專輯'),
              onRetry: _load,
            ),
            for (final c in _items) _CollectionCard(item: c),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.item});
  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/collection/${item.ctid}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(item.threads,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary)),
                  Text(tr('主題'),
                      style: TextStyle(fontSize: 10.5, color: faint(context))),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (item.desc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(item.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, height: 1.4, color: subtle(context))),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (item.author.isNotEmpty) item.author,
                        if (item.meta.isNotEmpty) item.meta,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: faint(context)),
                    ),
                    if (item.latest.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('${tr('最新')}：${item.latest}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: faint(context))),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 淘專輯內頁：專輯資訊 + 收錄的主題
class CollectionViewPage extends StatefulWidget {
  const CollectionViewPage({super.key, required this.ctid});
  final int ctid;

  @override
  State<CollectionViewPage> createState() => _CollectionViewPageState();
}

class _CollectionViewPageState extends State<CollectionViewPage> {
  CollectionView? _data;
  bool _loading = true;
  bool _busy = false;
  String? _err;
  int _page = 1;
  final _scroll = ScrollController();

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

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _err = null;
      if (page != null) _page = page;
    });
    try {
      final d = await api.fetchCollectionThreads(widget.ctid, page: _page);
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

  Future<void> _toggleFollow() async {
    final d = _data;
    if (d == null) return;
    setState(() => _busy = true);
    try {
      final r = await api.followCollection(widget.ctid, follow: !d.following);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: Text(d?.name ?? tr('淘專輯'))),
      bottomNavigationBar: d == null || d.list.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(d.name,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _toggleFollow,
                            child: Text(d.following ? tr('取消訂閱') : tr('訂閱')),
                          ),
                        ],
                      ),
                      if (d.author.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('${tr('專輯創建人')}：${d.author}',
                            style: TextStyle(fontSize: 12.5, color: faint(context))),
                      ],
                      if (d.follows.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('${d.follows} ${tr('人訂閱')}',
                            style: TextStyle(fontSize: 12.5, color: faint(context))),
                      ],
                      if (d.desc.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(d.desc,
                            style: const TextStyle(fontSize: 13.5, height: 1.6)),
                      ],
                    ],
                  ),
                ),
              ),
              if (d.list.isNotEmpty)
                ThreadListCard(list: d.list)
              else if (!_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(d.message ?? tr('這個專輯還沒有主題'),
                        style: TextStyle(fontSize: 13, color: faint(context))),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
