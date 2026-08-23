import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/favorites.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/external_link.dart';
import '../widgets/image_reveal.dart';
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
  ThreadExtras _extras = const ThreadExtras();
  final _revealImages = ValueNotifier<bool>(false);
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
    _revealImages.dispose();
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
    _loadExtras();
  }

  /// 回帖獎勵與附件只有桌面模板有，要多抓一次頁面（約 90 KB），
  /// 所以獨立於主流程之外跑，失敗也不影響帖子顯示
  Future<void> _loadExtras() async {
    try {
      final e = await api.fetchThreadExtras(widget.tid, page: _page);
      if (mounted) setState(() => _extras = e);
    } on DiscuzException {
      // 靜靜放棄
    }
  }

  Future<void> _fav() async {
    if (!await requireLogin(context, action: tr('收藏主題'))) return;
    if (!mounted) return;
    try {
      final r = await api.favoriteThread(widget.tid);
      if (!mounted) return;
      toast(context, r.message);
      // 「已收藏过本主题」也代表已收藏，一樣要記起來
      if (r.ok || r.message.contains('已收藏')) {
        await context.read<FavoriteStore>().add(widget.tid);
      }
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
      if (_data?.title.isNotEmpty ?? false) 'title': _data!.title,
    });
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final session = context.watch<SessionStore>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          d?.title.isNotEmpty == true ? d!.title : (d?.forumName ?? tr('主題')),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _revealImages,
            builder: (c, all, _) => context.watch<SettingsStore>().autoLoadImages
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: all ? tr('圖片已全部載入') : tr('全部載入圖片'),
                    icon: Icon(all
                        ? Icons.photo_library
                        : Icons.photo_library_outlined),
                    onPressed: all ? null : () => _revealImages.value = true,
                  ),
          ),
          if (session.loggedIn)
            Builder(builder: (c) {
              final faved = c.watch<FavoriteStore>().contains(widget.tid);
              return IconButton(
                icon: Icon(faved ? Icons.star : Icons.star_border),
                color: faved ? const Color(0xFFF6B93B) : null,
                tooltip: faved ? tr('已收藏') : tr('收藏'),
                onPressed: _fav,
              );
            }),
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
      body: ImageReveal(
        notifier: _revealImages,
        child: RefreshIndicator(
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
              if (_extras.prize != null) _PrizeBanner(prize: _extras.prize!),
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
              if (_extras.attachments.isNotEmpty)
                _AttachmentCard(items: _extras.attachments),
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
      ),
    );
  }
}

/// 附件清單。免費的點了直接開下載，付費的先讓使用者知道要花多少
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.items});
  final List<Attachment> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
          child: Text('${tr('附件')} · ${items.length}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: faint(context))),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                ListTile(
                  leading: Icon(
                    items[i].needsPay
                        ? Icons.lock_outline
                        : Icons.attach_file,
                    size: 22,
                  ),
                  title: Text(items[i].name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.35)),
                  subtitle: Text(
                    [
                      if (items[i].needsPay) '${tr('售價')} ${items[i].price}',
                      if (items[i].info.isNotEmpty) items[i].info,
                    ].join('　'),
                    style: TextStyle(fontSize: 11.5, color: faint(context)),
                  ),
                  trailing: Icon(
                      items[i].needsPay ? Icons.shopping_cart_outlined : Icons.download,
                      size: 18),
                  onTap: () => confirmExternal(
                    context,
                    items[i].url,
                    title: items[i].needsPay ? tr('購買附件') : tr('下載附件'),
                    note: items[i].needsPay
                        ? tr('購買要在論壇頁面上完成，App 會交給瀏覽器。')
                        : tr('App 不能直接存檔，下載會交給瀏覽器處理。'),
                  ),
                ),
                if (i != items.length - 1)
                  const Divider(height: 1, indent: 56, endIndent: 14),
              ],
            ],
          ),
        ),
      ],
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


/// 回帖獎勵橫幅
class _PrizeBanner extends StatelessWidget {
  const _PrizeBanner({required this.prize});
  final ThreadPrize prize;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.primary.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Icon(Icons.redeem_outlined, size: 22, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tr('回帖獎勵')}　${prize.pool}',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: c.primary),
                ),
                if (prize.rule.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(prize.rule,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: subtle(context))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
