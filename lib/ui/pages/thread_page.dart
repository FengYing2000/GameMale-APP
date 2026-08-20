import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_body.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({super.key, required this.tid});
  final int tid;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  ThreadData? _data;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchThread(widget.tid, page: _page);
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

  Future<void> _fav() async {
    try {
      final r = await api.favoriteThread(widget.tid);
      if (mounted) toast(context, r.message);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '收藏失敗：${e.message}');
    }
  }

  void _reply([PostItem? post]) {
    final uri = Uri(path: '/t/${widget.tid}/reply', queryParameters: {
      'fid': '${_data?.fid ?? 0}',
      'page': '$_page',
      if (post?.pid != null) 'repquote': '${post!.pid}',
      if (post != null && post.author.isNotEmpty) 'to': post.author,
    });
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.forumName ?? '主題'),
        actions: [
          IconButton(
              icon: const Icon(Icons.star_border), tooltip: '收藏', onPressed: _fav),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _reply(),
        tooltip: '回覆',
        child: const Icon(Icons.reply),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              if (_page == 1 && d.title.isNotEmpty)
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text.rich(
                    TextSpan(children: [
                      if (d.type.isNotEmpty)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Container(
                            margin: const EdgeInsets.only(right: 7),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: brand.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(d.type,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.primary)),
                          ),
                        ),
                      TextSpan(text: d.title),
                    ]),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
              if (d.poll case final poll?)
                PollCard(poll: poll, onVoted: _load),
              for (final p in d.posts) _PostCard(post: p, onReply: () => _reply(p)),
              PagerBar(
                pager: d.pager,
                onGo: (page) {
                  setState(() => _page = page);
                  _load();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onReply});
  final PostItem post;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(post.avatar,
                  size: 36,
                  onTap: post.uid == null ? null : () => context.push('/u/${post.uid}')),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(post.time, style: TextStyle(fontSize: 11.5, color: faint(context))),
                  ],
                ),
              ),
              if (post.floor.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(post.floor,
                      style: TextStyle(fontSize: 11.5, color: subtle(context))),
                ),
            ],
          ),
          const SizedBox(height: 10),
          PostBody(post.html),
          if (post.signature.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: ClipRect(
                child: PostBody(
                  post.signature,
                  textStyle: TextStyle(fontSize: 12.5, color: faint(context)),
                ),
              ),
            ),
          ],
          if (post.comments.isNotEmpty) _FloorComments(comments: post.comments),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReply,
              icon: const Icon(Icons.reply, size: 16),
              label: const Text('回覆'),
              style: TextButton.styleFrom(
                foregroundColor: subtle(context),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 樓中樓（dxksst 外掛）
class _FloorComments extends StatelessWidget {
  const _FloorComments({required this.comments});
  final List<FloorComment> comments;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Avatar(c.avatar,
                      size: 20,
                      onTap: c.uid == null ? null : () => context.push('/u/${c.uid}')),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${c.name}：',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: c.text),
                      ]),
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
