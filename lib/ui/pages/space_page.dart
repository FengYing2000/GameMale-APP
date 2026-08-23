import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../api/models.dart';
import '../../api/space.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/require_login.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 個人空間：記錄／日誌／相冊／主題／留言板／好友，全部走桌面模板
class SpacePage extends StatefulWidget {
  const SpacePage({super.key, required this.uid, this.tab = SpaceTab.home});
  final int uid;
  final SpaceTab tab;

  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _cache = <SpaceTab, SpaceData>{};
  SpaceTab _tab = SpaceTab.home;
  bool _loading = true;
  String? _err;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _tab = widget.tab;
    _tabs = TabController(
      length: SpaceTab.values.length,
      initialIndex: SpaceTab.values.indexOf(_tab),
      vsync: this,
    );
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final next = SpaceTab.values[_tabs.index];
      if (next == _tab) return;
      setState(() {
        _tab = next;
        _page = 1;
      });
      if (!_cache.containsKey(next)) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    final tab = _tab;
    setState(() {
      _loading = true;
      _err = null;
      if (page != null) _page = page;
    });
    try {
      final d = await api.fetchSpace(widget.uid, tab, page: _page);
      if (mounted) setState(() => _cache[tab] = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _leaveMessage() async {
    if (!await requireLogin(context, action: tr('留言'))) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('留言')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(hintText: tr('寫點什麼…')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(tr('送出'))),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final r = await api.postWall(
          widget.uid, text, _cache[SpaceTab.wall]?.formhash ?? '');
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('留言失敗：${e.message}'));
    }
  }

  void _open(SpaceItem it) {
    if (it.tid != null) {
      context.push('/t/${it.tid}');
      return;
    }
    if (it.albumId != null) {
      context.push('/album/${it.uid ?? widget.uid}/${it.albumId}');
      return;
    }
    // 日誌網址是 blog-<uid>-<blogid>.html
    final blog = RegExp(r'blog-(\d+)-(\d+)').firstMatch(it.url);
    if (blog != null) {
      context.push('/blog/${blog.group(1)}/${blog.group(2)}');
      return;
    }
    if (it.uid != null) {
      context.push('/u/${it.uid}');
      return;
    }
    if (it.url.isNotEmpty) _openExternal(it.url);
  }

  void _openExternal(String url) {
    if (url.isEmpty) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final d = _cache[_tab];
    final owner = d?.owner ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(owner.isEmpty ? tr('個人空間') : '$owner${tr('的空間')}'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in SpaceTab.values) Tab(text: tr(t.label))],
        ),
      ),
      floatingActionButton: _tab == SpaceTab.wall
          ? FloatingActionButton.extended(
              onPressed: _leaveMessage,
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('留言')),
            )
          : null,
      bottomNavigationBar: d == null || d.items.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (d != null && d.items.isEmpty && !_loading && _err == null)
              _EmptyReason(data: d)
            else
              ?StateBox.maybe(
                loading: _loading,
                error: _err,
                onRetry: _load,
              ),
            if (d != null && d.items.isNotEmpty) ..._body(d),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(SpaceData d) => switch (d.tab) {
        SpaceTab.home => [for (final b in d.items) _homeBlock(b)],
        SpaceTab.album => [_grid(d.items)],
        SpaceTab.friend => [_grid(d.items, avatarStyle: true)],
        SpaceTab.doing => [for (final it in d.items) _doingCard(it)],
        _ => [
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
      };

  Widget _homeBlock(SpaceItem block) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Text(block.title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: faint(context))),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final it in block.children)
                  ListTile(
                    dense: true,
                    onTap: () => _open(it),
                    leading: it.uid != null && it.image.isNotEmpty
                        ? Avatar(it.image, size: 32)
                        : null,
                    title: Text(it.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, height: 1.35)),
                  ),
              ],
            ),
          ),
        ],
      );

  /// 記錄要連回覆一起顯示，所以自己一張卡
  Widget _doingCard(SpaceItem it) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (it.avatar.isNotEmpty) ...[
                    GestureDetector(
                      onTap: it.uid == null
                          ? null
                          : () => context.push('/u/${it.uid}'),
                      child: Avatar(it.avatar, size: 30),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(it.author,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(it.date,
                      style: TextStyle(fontSize: 11.5, color: faint(context))),
                ],
              ),
              const SizedBox(height: 8),
              Text(it.title,
                  style: const TextStyle(fontSize: 14.5, height: 1.5)),
              if (it.children.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in it.children)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: RichText(
                            text: TextSpan(
                              style: DefaultTextStyle.of(context)
                                  .style
                                  .copyWith(fontSize: 13, height: 1.45),
                              children: [
                                TextSpan(
                                  text: '${c.author}：',
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.primary),
                                ),
                                TextSpan(text: c.title),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _grid(List<SpaceItem> items, {bool avatarStyle = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: avatarStyle ? 4 : 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: avatarStyle ? .82 : .78,
          ),
          itemBuilder: (c, i) {
            final it = items[i];
            return InkWell(
              onTap: () => _open(it),
              onLongPress: it.uid == null
                  ? null
                  : () => context.push('/space/${it.uid}'),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  Expanded(
                    child: avatarStyle
                        ? Avatar(it.avatar, size: 56)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: it.image.isEmpty
                                ? Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(Icons.photo_outlined),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: it.image,
                                    httpHeaders: Api.imageHeaders,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorWidget: (c, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  if (it.meta.isNotEmpty)
                    Text(it.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: faint(context))),
                ],
              ),
            );
          },
        ),
      );

  Widget _tile(SpaceItem it) => ListTile(
        onTap: () => _open(it),
        leading: it.avatar.isEmpty ? null : Avatar(it.avatar, size: 36),
        title: Text(it.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4)),
        subtitle: (it.author.isEmpty && it.date.isEmpty && it.meta.isEmpty)
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  [it.author, it.date, it.meta]
                      .where((s) => s.trim().isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: faint(context)),
                ),
              ),
        trailing: it.image.isEmpty
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: it.image,
                  httpHeaders: Api.imageHeaders,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                  errorWidget: (c, _, _) => const SizedBox.shrink(),
                ),
              ),
      );
}

/// 空的原因分三種：要登入、被隱私設定擋住、真的沒東西。
/// 全部混成「沒有相冊」會讓人以為對方真的沒有
class _EmptyReason extends StatelessWidget {
  const _EmptyReason({required this.data});
  final SpaceData data;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = data.needsLogin
        ? (Icons.lock_outline, tr('要登入才看得到'))
        : data.restricted
            ? (Icons.visibility_off_outlined, tr('對方設了隱私限制'))
            : (Icons.inbox_outlined, '${tr('沒有')}${tr(data.tab.label)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 60, 36, 20),
      child: Column(
        children: [
          Icon(icon, size: 34, color: faint(context)),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (data.message != null && data.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              data.message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.7, color: faint(context)),
            ),
          ],
          if (data.needsLogin) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.push('/login'),
              child: Text(tr('前往登入')),
            ),
          ],
        ],
      ),
    );
  }
}
