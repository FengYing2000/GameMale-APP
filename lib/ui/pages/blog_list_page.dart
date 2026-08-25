import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../api/space.dart' as api;
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/login_required.dart';
import '../widgets/pager_bar.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_box.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      if (mounted) setState(() => _loading = false);
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
                            ? const Icon(Icons.lock_outline, size: 14)
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
        trailing: it.image.isEmpty
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
