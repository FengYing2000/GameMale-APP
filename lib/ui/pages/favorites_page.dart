import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../store/favorites.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/external_link.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 我的收藏。論壇分成帖子／版塊／群組／日誌／相冊，之前只做了前兩種
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<FavoriteItem> _items = const [];
  PageInfo _pager = const PageInfo();
  String _type = 'all';
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

  Future<void> _load({int? page}) async {
    final uid = context.read<SessionStore>().uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _err = tr('尚未登入');
      });
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
      if (page != null) _page = page;
    });
    try {
      final r = await api.fetchFavoriteList(uid, type: _type, page: _page);
      if (mounted) {
        setState(() {
          _items = r.items;
          _pager = r.pager;
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  Future<void> _remove(FavoriteItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('取消收藏')),
        content: Text(it.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(tr('取消收藏'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await api.unfavorite(it.favid);
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      if (!r.ok) return;
      setState(() => _items = _items.where((x) => x.favid != it.favid).toList());
      // 帖子的星星是靠這份清單判斷的，順手同步
      if (it.type == 'thread' && it.targetId != null) {
        await context.read<FavoriteStore>().remove(it.targetId!);
      }
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '${tr('取消收藏失敗：')}${e.message}');
    }
  }

  void _open(FavoriteItem it) {
    final id = it.targetId;
    switch (it.type) {
      case 'thread' when id != null:
        context.push('/t/$id');
      case 'forum' when id != null:
        context.push('/f/$id');
      case 'group' when id != null:
        context.push('/g/$id');
      case 'blog' when id != null:
        final m = RegExp(r'blog-(\d+)-(\d+)').firstMatch(it.url);
        if (m != null) {
          context.push('/blog/${m.group(1)}/${m.group(2)}');
        } else {
          openInApp(context, it.url, title: it.title);
        }
      default:
        openInApp(context, it.url, title: it.title);
    }
  }

  static IconData _iconOf(String type) => switch (type) {
        'thread' => LucideIcons.fileText,
        'forum' => LucideIcons.folder,
        'group' => LucideIcons.users,
        'blog' => LucideIcons.notebookPen,
        'album' => LucideIcons.images,
        _ => LucideIcons.star,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('我的收藏'))),
      bottomNavigationBar: _items.isEmpty
          ? null
          : StickyPager(pager: _pager, onGo: (p) => _load(page: p)),
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
                  for (final t in favoriteTypes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(t.name)),
                        selected: _type == t.type,
                        onSelected: (_) {
                          setState(() {
                            _type = t.type;
                            _page = 1;
                          });
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
              empty: !_loading && _err == null && _items.isEmpty,
              emptyText: tr('這一類還沒有收藏'),
              onRetry: _load,
            ),
            if (_items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      ListTile(
                        onTap: () => _open(_items[i]),
                        leading: Icon(_iconOf(_items[i].type), size: 20),
                        title: Text(_items[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, height: 1.4)),
                        subtitle: _items[i].date.isEmpty
                            ? null
                            : Text(_items[i].date,
                                style: TextStyle(
                                    fontSize: 11.5, color: faint(context))),
                        // 星星容易被當成「收藏」，取消收藏用垃圾桶才不會誤解
                        trailing: IconButton(
                          tooltip: tr('取消收藏'),
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          onPressed: () => _remove(_items[i]),
                        ),
                      ),
                      if (i != _items.length - 1)
                        const Divider(height: 1, indent: 56, endIndent: 14),
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
