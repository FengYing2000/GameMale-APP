import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/discuz.dart' as discuz;
import 'package:gm_api/group.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/pager_bar.dart';
import '../widgets/require_login.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';
import '../widgets/toast.dart';

/// 群組。只有桌面模板，所以走 desktop 抓再自己排版
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.fid});
  final int fid;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  GroupData? _data;
  bool _loading = true;
  bool _busy = false;
  String? _err;
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
      final d = await api.fetchGroup(widget.fid, page: _page);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 加入是一步就成立的（沒有確認頁），所以先問一次
  Future<void> _join() async {
    final d = _data;
    if (d == null) return;
    if (!await requireLogin(context, action: tr('加入群組'))) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('加入群組')),
        content: Text('${tr('確定要加入「')}${d.name}${tr('」嗎？')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('加入'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.joinGroup(widget.fid);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quit() async {
    final d = _data;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('退出群組')),
        content: Text('${tr('確定要退出「')}${d.name}${tr('」嗎？')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('退出'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.quitGroup(widget.fid, formhash: d.formhash);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite() async {
    final d = _data;
    if (d == null || d.favoriteUrl.isEmpty) return;
    if (!await requireLogin(context, action: tr('收藏群組'))) return;
    if (!mounted) return;
    try {
      final r = await discuz.favoriteByUrl(d.favoriteUrl);
      if (mounted) toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          d?.name.isNotEmpty == true ? d!.name : tr('群組'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (d != null)
            IconButton(
              tooltip: tr('成員列表'),
              icon: const Icon(LucideIcons.usersRound),
              onPressed: () => context.push(Uri(
                path: '/g/${widget.fid}/members',
                queryParameters: {'name': d.name},
              ).toString()),
            ),
        ],
      ),
      floatingActionButton: (d != null && d.joined)
          ? FloatingActionButton(
              onPressed: () => context.push('/f/${widget.fid}/post'),
              tooltip: tr('發表主題'),
              child: const Icon(LucideIcons.squarePen),
            )
          : null,
      bottomNavigationBar: d == null || d.threads.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              if (d.desc.isNotEmpty || d.icon.isNotEmpty) _header(d),
              if (d.threads.isEmpty && !_loading && _err == null) _empty(d),
              if (d.threads.isNotEmpty) ThreadListCard(list: d.threads),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(GroupData d) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.icon.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: d.icon,
                        httpHeaders: Api.imageHeaders,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (c, _, _) =>
                            const Icon(LucideIcons.users),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          children: [
                            if (d.level.isNotEmpty)
                              Text(d.level,
                                  style: TextStyle(
                                      fontSize: 12, color: faint(context))),
                            if (d.points.isNotEmpty)
                              Text('${tr('積分')} ${d.points}',
                                  style: TextStyle(
                                      fontSize: 12, color: faint(context))),
                          ],
                        ),
                        if (d.master.isNotEmpty)
                          GestureDetector(
                            onTap: d.masterUid == null
                                ? null
                                : () => context.push('/u/${d.masterUid}'),
                            child: Text('${tr('群主')}：${d.master}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: d.masterUid == null
                                        ? faint(context)
                                        : Theme.of(context).colorScheme.primary)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (d.desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(d.desc,
                    style: TextStyle(
                        fontSize: 13.5, height: 1.7, color: subtle(context))),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (d.joined)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _quit,
                      icon: const Icon(LucideIcons.logOut, size: 16),
                      label: Text(tr('退出群組')),
                    )
                  else if (d.canJoin)
                    FilledButton.icon(
                      onPressed: _busy ? null : _join,
                      icon: const Icon(LucideIcons.userPlus, size: 16),
                      label: Text(tr('加入群組')),
                    ),
                  const SizedBox(width: 10),
                  if (d.favoriteUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _favorite,
                      icon: const Icon(LucideIcons.star, size: 16),
                      label: Text(tr('收藏')),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _empty(GroupData d) => Padding(
        padding: const EdgeInsets.fromLTRB(36, 40, 36, 20),
        child: Column(
          children: [
            Icon(d.needsLogin ? LucideIcons.lock : LucideIcons.users,
                size: 34, color: faint(context)),
            const SizedBox(height: 14),
            Text(
              d.message ?? tr('這個群組沒有主題'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.7),
            ),
            if (d.canJoin && !d.joined) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _join,
                icon: const Icon(LucideIcons.userPlus, size: 18),
                label: Text(tr('加入群組')),
              ),
            ],
          ],
        ),
      );
}
