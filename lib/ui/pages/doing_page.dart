import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../store/session.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/post_body.dart';
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

  Future<void> _reply(DoingItem item) async {
    if (!await requireLogin(context, action: tr('回覆記錄'))) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${tr('回覆')} ${item.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: tr('說點什麼…')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(tr('送出'))),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final r = await api.replyDoing(item.doid, text,
          formhash: _data?.formhash ?? '');
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('回覆失敗：') + e.message);
    }
  }

  Future<void> _delete(String url, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(what),
        content: Text(tr('確定要刪除嗎？刪了就找不回來了。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(tr('刪除'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.confirmAndSubmit(url, what);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, what + tr('失敗：') + e.message);
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
              child: const Icon(LucideIcons.squarePen),
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
                      _DoingRow(
                        item: d.items[i],
                        onReply: () => _reply(d.items[i]),
                        onDelete: d.items[i].deleteUrl.isEmpty
                            ? null
                            : () => _delete(d.items[i].deleteUrl, tr('刪除記錄')),
                        onDeleteComment: (c) =>
                            _delete(c.deleteUrl, tr('刪除回覆')),
                      ),
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
  const _DoingRow({
    required this.item,
    required this.onReply,
    this.onDelete,
    required this.onDeleteComment,
  });
  final DoingItem item;
  final VoidCallback onReply;
  final VoidCallback? onDelete;
  final void Function(DoingComment) onDeleteComment;

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
                // 記錄裡常夾表情圖，純文字會把它們吃掉
                if (item.html.isNotEmpty)
                  PostBody(item.html,
                      textStyle: const TextStyle(fontSize: 14, height: 1.5))
                else
                  Text(item.message,
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(item.time,
                        style: TextStyle(fontSize: 11.5, color: faint(context))),
                    const Spacer(),
                    _action(context, tr('回覆'), onReply),
                    if (onDelete != null) ...[
                      const SizedBox(width: 14),
                      _action(context, tr('刪除'), onDelete!),
                    ],
                  ],
                ),
                if (item.comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in item.comments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(
                                        text: '${c.author}：',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ),
                                      TextSpan(text: c.text),
                                      if (c.time.isNotEmpty)
                                        TextSpan(
                                          text: '  ${c.time}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: faint(context)),
                                        ),
                                    ]),
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.5),
                                  ),
                                ),
                                if (c.deleteUrl.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => onDeleteComment(c),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8, top: 2),
                                      child: Icon(LucideIcons.x,
                                          size: 14, color: faint(context)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext c, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(c).colorScheme.primary)),
      );
}
