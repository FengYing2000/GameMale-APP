import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/http.dart';
import '../../api/models.dart';
import '../../api/space.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_body.dart';
import '../widgets/require_login.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 日誌內頁：內文、表態、表態過的人、評論、作者的其他日誌
class BlogPage extends StatefulWidget {
  const BlogPage({super.key, required this.uid, required this.blogId});
  final int uid;
  final int blogId;

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  BlogData? _data;
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchBlog(widget.uid, widget.blogId);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _comment() async {
    final d = _data;
    if (d == null) return;
    if (!await requireLogin(context, action: tr('留言'))) return;
    if (!mounted) return;

    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('發表評論')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(hintText: tr('寫點什麼…')),
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
      final r = await api.postBlogComment(widget.blogId, text, d.formhash);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('留言失敗：${e.message}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      floatingActionButton: d == null || d.html.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _comment,
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('評論')),
            ),
      appBar: AppBar(
        title: Text(
          d?.title.isNotEmpty == true ? d!.title : tr('日誌'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.html.isEmpty ?? false),
              emptyText: d?.message ?? '',
              onRetry: _load,
            ),
            if (d != null && d.html.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(d.title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
              ),
              if (d.meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(d.meta,
                      style: TextStyle(fontSize: 12, color: faint(context))),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: PostBody(d.html),
                ),
              ),
              if (d.reactions.isNotEmpty) _reactions(d),
              if (d.reactedBy.isNotEmpty) _reactedBy(d),
              if (d.comments.isNotEmpty) _comments(d),
              if (d.otherPosts.isNotEmpty) _others(d),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reactions(BlogData d) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Row(
            children: [
              for (final r in d.reactions)
                Expanded(
                  child: Column(
                    children: [
                      if (r.icon.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: r.icon,
                          httpHeaders: Api.imageHeaders,
                          height: 28,
                          errorWidget: (c, _, _) =>
                              const Icon(Icons.emoji_emotions_outlined, size: 24),
                        ),
                      const SizedBox(height: 6),
                      Text('${r.count}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: faint(context))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _reactedBy(BlogData d) => _block(
        d.reactedCount.isEmpty ? tr('剛表態過的朋友') : d.reactedCount,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in d.reactedBy)
                SizedBox(
                  width: 56,
                  child: Column(
                    children: [
                      Avatar(p.avatar,
                          size: 40,
                          onTap: p.uid == null
                              ? null
                              : () => context.push('/u/${p.uid}')),
                      const SizedBox(height: 4),
                      Text(p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _comments(BlogData d) => _block(
        '${tr('評論')} · ${d.comments.length}',
        Column(
          children: [
            for (var i = 0; i < d.comments.length; i++) ...[
              _commentTile(d.comments[i]),
              if (i != d.comments.length - 1)
                const Divider(height: 1, indent: 60, endIndent: 14),
            ],
          ],
        ),
      );

  Widget _commentTile(BlogComment c) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(c.avatar,
                size: 32,
                onTap: c.uid == null ? null : () => context.push('/u/${c.uid}')),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.author,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      Text(c.date,
                          style:
                              TextStyle(fontSize: 11, color: faint(context))),
                    ],
                  ),
                  if (c.quote.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(c.quote,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.5, color: faint(context))),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(c.text,
                      style: const TextStyle(fontSize: 14, height: 1.55)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _others(BlogData d) => _block(
        tr('作者的其他日誌'),
        Column(
          children: [
            for (final o in d.otherPosts)
              ListTile(
                dense: true,
                leading: Icon(Icons.article_outlined, size: 18, color: faint(context)),
                title: Text(o.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5)),
                onTap: () {
                  final m = RegExp(r'blog-(\d+)-(\d+)').firstMatch(o.url);
                  if (m != null) {
                    context.push('/blog/${m.group(1)}/${m.group(2)}');
                  }
                },
              ),
          ],
        ),
      );

  Widget _block(String title, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: faint(context))),
          ),
          Card(clipBehavior: Clip.antiAlias, child: child),
        ],
      );
}
