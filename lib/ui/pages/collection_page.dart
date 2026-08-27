import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/external_link.dart';
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
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final t in item.tags)
                            GestureDetector(
                              onTap: () => context.push(Uri(
                                path: '/f/0/search',
                                queryParameters: {'q': t.keyword},
                              ).toString()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('#${t.name}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Theme.of(context).colorScheme.primary)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (item.author.isNotEmpty)
                          GestureDetector(
                            onTap: item.authorUid == null
                                ? null
                                : () => context.push('/u/${item.authorUid}'),
                            child: Text(item.author,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: item.authorUid == null
                                        ? faint(context)
                                        : Theme.of(context).colorScheme.primary)),
                          ),
                        if (item.meta.isNotEmpty)
                          Expanded(
                            child: Text('　${item.meta}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5, color: faint(context))),
                          ),
                      ],
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

  /// 向作者推薦主題（貼主題網址）
  Future<void> _recommend() async {
    final d = _data;
    if (d == null) return;
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('向作者推薦主題')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('貼上主題網址')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(tr('推薦'))),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    try {
      final r = await api.recommendThreadToCollection(widget.ctid, url,
          formhash: d.formhash);
      if (mounted) toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  /// 發表評論（可附評分）
  Future<void> _comment() async {
    final d = _data;
    if (d == null) return;
    final ctrl = TextEditingController();
    var score = 5;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 0, 18, MediaQuery.of(c).viewInsets.bottom + 18),
        child: StatefulBuilder(
          builder: (c, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('評價淘專輯'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var s = 1; s <= 5; s++)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setSheet(() => score = s),
                      icon: Icon(
                          s <= score ? Icons.star : Icons.star_border,
                          color: const Color(0xFFF6B93B)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: tr('說說你的看法（可留空）'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('發表評論')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.commentCollection(widget.ctid, ctrl.text.trim(),
          score: score, formhash: d.formhash);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  /// 編輯淘專輯（名稱／簡介／標籤）
  Future<void> _edit() async {
    final d = _data;
    if (d == null) return;
    final title = TextEditingController(text: d.name);
    final desc = TextEditingController(text: d.desc);
    final keyword = TextEditingController(
        text: d.list.isEmpty ? '' : ''); // 標籤原文不在檢視頁，留空讓使用者填
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 0, 18, MediaQuery.of(c).viewInsets.bottom + 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('編輯淘專輯'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                decoration: InputDecoration(
                    labelText: tr('淘專輯名'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: desc,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: tr('簡介'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyword,
                decoration: InputDecoration(
                    labelText: tr('標籤（空格分隔，最多 5 個）'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('儲存')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.editCollection(widget.ctid,
          title: title.text.trim(),
          desc: desc.text.trim(),
          keyword: keyword.text.trim(),
          formhash: d.formhash);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _delete() async {
    final d = _data;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('刪除淘專輯')),
        content: Text(tr('確定要刪除「${d.name}」嗎？刪了就找不回來了。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('刪除'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.removeCollection(widget.ctid, formhash: d.formhash);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) context.pop();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.name ?? tr('淘專輯')),
        actions: [
          if (d != null && d.mine)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.ellipsisVertical),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit();
                  case 'delete':
                    _delete();
                  case 'invite':
                    if (d.inviteUrl.isNotEmpty) {
                      openInApp(context, d.inviteUrl, title: tr('邀請維護'));
                    }
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'edit', child: Text(tr('編輯'))),
                if (d.inviteUrl.isNotEmpty)
                  PopupMenuItem(value: 'invite', child: Text(tr('邀請維護'))),
                PopupMenuItem(value: 'delete', child: Text(tr('刪除'))),
              ],
            ),
        ],
      ),
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
                        GestureDetector(
                          onTap: d.authorUid == null
                              ? null
                              : () => context.push('/u/${d.authorUid}'),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '${tr('專輯創建人')}：',
                                style: TextStyle(
                                    fontSize: 12.5, color: faint(context))),
                            TextSpan(
                                text: d.author,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: d.authorUid == null
                                        ? faint(context)
                                        : Theme.of(context).colorScheme.primary)),
                          ])),
                        ),
                      ],
                      Row(
                        children: [
                          if (d.follows.isNotEmpty)
                            Text('${d.follows} ${tr('人訂閱')}',
                                style: TextStyle(fontSize: 12.5, color: faint(context))),
                          if (d.rating.isNotEmpty) ...[
                            if (d.follows.isNotEmpty)
                              Text('　·　',
                                  style: TextStyle(fontSize: 12.5, color: faint(context))),
                            Text(d.rating,
                                style: TextStyle(fontSize: 12.5, color: faint(context))),
                          ],
                        ],
                      ),
                      if (d.desc.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(d.desc,
                            style: const TextStyle(fontSize: 13.5, height: 1.6)),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _recommend,
                            icon: const Icon(LucideIcons.send, size: 15),
                            label: Text(tr('推薦主題')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _comment,
                            icon: const Icon(LucideIcons.star, size: 15),
                            label: Text(tr('評分評論')),
                          ),
                        ],
                      ),
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
              if (d.comments.isNotEmpty) _CommentsCard(comments: d.comments),
            ],
          ],
        ),
      ),
    );
  }
}

/// 淘專輯的最新評論
class _CommentsCard extends StatelessWidget {
  const _CommentsCard({required this.comments});
  final List<CollectionComment> comments;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(tr('最新評論'),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          for (var i = 0; i < comments.length; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: comments[i].uid == null
                                  ? null
                                  : () => context.push('/u/${comments[i].uid}'),
                              child: Text(comments[i].author,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          Theme.of(context).colorScheme.primary)),
                            ),
                            const SizedBox(width: 8),
                            if (comments[i].stars > 0)
                              Row(
                                children: [
                                  for (var s = 0; s < comments[i].stars; s++)
                                    const Icon(Icons.star,
                                        size: 12, color: Color(0xFFF6B93B)),
                                ],
                              ),
                            const Spacer(),
                            if (comments[i].date.isNotEmpty)
                              Text(comments[i].date,
                                  style: TextStyle(
                                      fontSize: 11, color: faint(context))),
                          ],
                        ),
                        if (comments[i].text.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(comments[i].text,
                              style: const TextStyle(fontSize: 13, height: 1.5)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i != comments.length - 1)
              const Divider(height: 1, indent: 14, endIndent: 14),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
