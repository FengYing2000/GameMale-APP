import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../store/session.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 記錄廣場（Discuz 的「记录」）
class DoingPageView extends StatefulWidget {
  const DoingPageView({super.key});

  @override
  State<DoingPageView> createState() => _DoingPageViewState();
}

class _DoingPageViewState extends State<DoingPageView> {
  String _view = 'all';
  DoingPage? _data;
  bool _loading = true;
  int _page = 1;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchDoing(view: _view, page: _page);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    if (!await requireLogin(context, action: tr('發布記錄'))) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('發布記錄')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          maxLength: 200,
          decoration: InputDecoration(hintText: tr('說說你在做什麼…')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(tr('發布'))),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final r = await api.postDoing(text, formhash: _data?.formhash ?? '');
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('發布失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final session = context.watch<SessionStore>();

    return Scaffold(
      appBar: AppBar(title: Text(tr('記錄廣場'))),
      bottomNavigationBar: d == null || d.items.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
      floatingActionButton: session.loggedIn
          ? FloatingActionButton(
              onPressed: _busy ? null : _compose,
              tooltip: tr('發布記錄'),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                children: [
                  // 我和好友／我的記錄需要帳號，訪客不顯示
                  for (final v in api.doingViews)
                    if (!v.needsLogin || session.loggedIn)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(v.name)),
                        selected: _view == v.key,
                        onSelected: (_) {
                          setState(() => _view = v.key);
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
              empty: !_loading && _err == null && (d?.items.isEmpty ?? false),
              emptyText: tr('還沒有人留下記錄'),
              onRetry: _load,
            ),
            if (d != null && d.items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < d.items.length; i++) ...[
                      _DoingRow(item: d.items[i]),
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

class _DoingRow extends StatelessWidget {
  const _DoingRow({required this.item});
  final DoingItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                Text(item.name,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(item.message, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 4),
                Text(item.time, style: TextStyle(fontSize: 11.5, color: faint(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
