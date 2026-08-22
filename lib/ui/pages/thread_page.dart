import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/login_required.dart';
import '../widgets/pager_bar.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_body.dart';
import '../widgets/rate_sheet.dart';
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
    if (!await requireLogin(context, action: tr('收藏主題'))) return;
    if (!mounted) return;
    try {
      final r = await api.favoriteThread(widget.tid);
      if (mounted) toast(context, r.message);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('收藏失敗：${e.message}'));
    }
  }

  Future<void> _reply([PostItem? post]) async {
    if (!await requireLogin(context, action: tr('回覆主題'))) return;
    if (!mounted) return;
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
    final session = context.watch<SessionStore>();

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.forumName ?? tr('主題')),
        actions: [
          if (session.loggedIn)
            IconButton(
                icon: const Icon(Icons.star_border), tooltip: tr('收藏'), onPressed: _fav),
        ],
      ),
      floatingActionButton: session.loggedIn
          ? FloatingActionButton(
              onPressed: () => _reply(),
              tooltip: tr('回覆'),
              child: const Icon(Icons.reply),
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
            if (d?.requiresLogin ?? false)
              const LoginRequired()
            else
              ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null && !d.requiresLogin) ...[
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
              for (final p in d.posts)
                _PostCard(
                  post: p,
                  onReply: session.loggedIn ? () => _reply(p) : null,
                  onRate: (!session.loggedIn || p.pid == null || d.fid == null)
                      ? null
                      : () async {
                          final ok = await showRateSheet(context,
                              fid: d.fid!, tid: widget.tid, pid: p.pid!);
                          if (ok) _load();
                        },
                  onShowRatings: p.pid == null
                      ? null
                      : () => showRatings(context, tid: widget.tid, pid: p.pid!),
                  onEdit: (p.pid == null ||
                          d.fid == null ||
                          p.uid == null ||
                          p.uid != context.read<SessionStore>().uid)
                      ? null
                      : () async {
                          final ok = await context.push<bool>(Uri(
                            path: '/t/${widget.tid}/edit/${p.pid}',
                            queryParameters: {'fid': '${d.fid}'},
                          ).toString());
                          if (ok == true) _load();
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
  const _PostCard({
    required this.post,
    this.onReply,
    this.onRate,
    this.onShowRatings,
    this.onEdit,
  });
  final PostItem post;
  final VoidCallback? onReply;
  final VoidCallback? onRate;
  final VoidCallback? onShowRatings;

  /// 只有自己的樓層才會有值
  final VoidCallback? onEdit;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(tr('編輯')),
                  style: TextButton.styleFrom(
                    foregroundColor: subtle(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onShowRatings != null)
                TextButton.icon(
                  onPressed: onShowRatings,
                  icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                  label: Text(tr('評分紀錄')),
                  style: TextButton.styleFrom(
                    foregroundColor: faint(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onRate != null)
                TextButton.icon(
                  onPressed: onRate,
                  icon: const Icon(Icons.thumb_up_outlined, size: 16),
                  label: Text(tr('評分')),
                  style: TextButton.styleFrom(
                    foregroundColor: subtle(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (onReply != null)
              TextButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.reply, size: 16),
                label: Text(tr('回覆')),
                style: TextButton.styleFrom(
                  foregroundColor: subtle(context),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
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
