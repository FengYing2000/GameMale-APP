import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../store/session.dart';
import '../../api/models.dart';
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
  int _typeid = 0;
  ForumTab _tab = ForumTab(name: tr('全部'));
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchForum(
        widget.fid,
        page: _page,
        filter: _tab.filter,
        orderby: _tab.orderby,
        digest: _tab.digest,
        typeid: _typeid,
      );
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

  void _pickTab(ForumTab t) {
    setState(() {
      _tab = t;
      _typeid = 0;
      _page = 1;
    });
    _load();
  }

  void _pickType(ThreadType t) {
    setState(() {
      _typeid = t.typeid;
      _tab = ForumTab(name: tr('全部'));
      _page = 1;
    });
    Navigator.of(context).pop();
    _load();
  }

  void _openMenu() {
    final d = _data;
    if (d == null) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.subforums.isNotEmpty) ...[
                Text(tr('子版塊'), style: TextStyle(fontSize: 12, color: faint(c))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in d.subforums)
                      ActionChip(
                        label: Text(s.name),
                        onPressed: () {
                          Navigator.of(c).pop();
                          context.push('/f/${s.fid}');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (d.types.isNotEmpty) ...[
                Text(tr('主題分類'), style: TextStyle(fontSize: 12, color: faint(c))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in d.types)
                      FilterChip(
                        label: Text(t.count.isEmpty ? t.name : '${t.name} ${t.count}'),
                        selected: _typeid == t.typeid,
                        onSelected: (_) => _pickType(t),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.name ?? tr('板塊')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: tr('在本版搜尋'),
            onPressed: () => context.push(Uri(
              path: '/f/${widget.fid}/search',
              queryParameters: {'name': d?.name ?? ''},
            ).toString()),
          ),
          if (d != null && (d.subforums.isNotEmpty || d.types.isNotEmpty))
            IconButton(icon: const Icon(Icons.tune), tooltip: tr('分類'), onPressed: _openMenu),
        ],
      ),
      floatingActionButton: context.watch<SessionStore>().loggedIn
          ? FloatingActionButton(
              onPressed: () => context.push('/f/${widget.fid}/post'),
              tooltip: tr('發表新主題'),
              child: const Icon(Icons.edit_outlined),
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
                        child: Text(m, style: TextStyle(fontSize: 12, color: faint(context))),
                      ),
                  ],
                ),
              ),
            // 子板塊直接列出來 —— 原本只藏在右上角選單裡，很難發現
            if (d != null && d.subforums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final sub in d.subforums)
                      ActionChip(
                        avatar: const Icon(Icons.folder_outlined, size: 15),
                        label: Text(sub.name, style: const TextStyle(fontSize: 13)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => context.push('/f/${sub.fid}'),
                      ),
                  ],
                ),
              ),
            if (d != null && d.tabs.isNotEmpty)
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  children: [
                    for (final t in d.tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.name),
                          selected: _typeid == 0 &&
                              _tab.filter == t.filter &&
                              _tab.orderby == t.orderby,
                          onSelected: (_) => _pickTab(t),
                        ),
                      ),
                  ],
                ),
              ),
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
}
