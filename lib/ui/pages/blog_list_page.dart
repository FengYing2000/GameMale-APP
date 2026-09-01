import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/models.dart';
import 'package:gm_api/space.dart' as api;
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/external_link.dart';
import '../widgets/login_required.dart';
import '../widgets/pager_bar.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 日誌廣場。跟記錄廣場同一套：隨便看看誰都能看，好友／我的要登入
class BlogListPageView extends StatefulWidget {
  const BlogListPageView({super.key});

  @override
  State<BlogListPageView> createState() => _BlogListPageViewState();
}

class _BlogListPageViewState extends State<BlogListPageView> {
  BlogListPage? _data;
  bool _loading = true;
  String? _err;
  String _view = 'all';
  int _catid = 0;
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
      final d = await api.fetchBlogList(_view, page: _page, catid: _catid);
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

  void _switch(String view) {
    setState(() {
      _view = view;
      _catid = 0;
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final loggedIn = context.watch<SessionStore>().loggedIn;
    // 好友／我的都要登入，先擋在前面比較好懂
    final locked = !loggedIn &&
        blogViews.any((v) => v.key == _view && v.needsLogin);

    return Scaffold(
      appBar: AppBar(title: Text(tr('日誌'))),
      bottomNavigationBar: d == null || d.items.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
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
                  for (final v in blogViews)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: v.needsLogin && !loggedIn
                            ? const Icon(LucideIcons.lock, size: 14)
                            : null,
                        label: Text(tr(v.name)),
                        selected: _view == v.key,
                        onSelected: (_) => _switch(v.key),
                      ),
                    ),
                ],
              ),
            ),
            if (d != null && d.categories.isNotEmpty && _view == 'all')
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr('全部')),
                        selected: _catid == 0,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() {
                            _catid = 0;
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    ),
                    for (final c in d.categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.name,
                              style: const TextStyle(fontSize: 12.5)),
                          selected: _catid == c.catid,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() {
                              _catid = c.catid;
                              _page = 1;
                            });
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            if (locked)
              LoginRequired(message: tr('登入之後才看得到這一區的日誌'))
            else ...[
              ?StateBox.maybe(
                loading: _loading,
                error: _err,
                empty: !_loading && _err == null && (d?.items.isEmpty ?? false),
                emptyText: d?.message ?? tr('這裡沒有日誌'),
                onRetry: _load,
              ),
              if (d != null && d.items.isNotEmpty)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < d.items.length; i++) ...[
                        _tile(d.items[i]),
                        if (i != d.items.length - 1)
                          const Divider(height: 1, indent: 14, endIndent: 14),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _act(String url, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(what),
        content: Text('${tr('確定要')}$what${tr('嗎？')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(what)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.blogAction(url, what);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '$what${tr('失敗：')}${e.message}');
    }
  }

  Widget _tile(SpaceItem it) => ListTile(
        onTap: () {
          final m = RegExp(r'blog-(\d+)-(\d+)').firstMatch(it.url);
          if (m != null) context.push('/blog/${m.group(1)}/${m.group(2)}');
        },
        leading: it.avatar.isEmpty
            ? null
            : Avatar(it.avatar,
                size: 38,
                onTap: it.uid == null ? null : () => context.push('/u/${it.uid}')),
        title: Text(it.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, height: 1.4)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (it.body.isNotEmpty)
                Text(it.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.45, color: subtle(context))),
              const SizedBox(height: 3),
              Text(
                [it.author, it.date, it.meta]
                    .where((s) => s.trim().isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: faint(context)),
              ),
            ],
          ),
        ),
        trailing: it.actions.isNotEmpty
            ? PopupMenuButton<String>(
                tooltip: tr('管理'),
                itemBuilder: (c) => [
                  if (it.actions.containsKey('edit'))
                    PopupMenuItem(value: 'edit', child: Text(tr('編輯'))),
                  if (it.actions.containsKey('stick'))
                    PopupMenuItem(value: 'stick', child: Text(tr('置頂'))),
                  if (it.actions.containsKey('delete'))
                    PopupMenuItem(value: 'delete', child: Text(tr('刪除'))),
                ],
                onSelected: (v) {
                  final url = it.actions[v] ?? '';
                  if (url.isEmpty) return;
                  if (v == 'edit') {
                    // 論壇的日誌編輯器有分類、隱私、標籤那一整套
                    openInApp(context, url, title: tr('編輯日誌'));
                  } else {
                    _act(url, v == 'stick' ? tr('置頂') : tr('刪除'));
                  }
                },
              )
            : it.image.isEmpty
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SmartImage(
                  src: it.image,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  errorWidget: const SizedBox.shrink(),
                ),
              ),
      );
}
