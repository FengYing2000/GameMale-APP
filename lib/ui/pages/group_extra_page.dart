import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/group.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';

/// 我參與的 / 我管理的 群組
class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({super.key});

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  String _view = 'join';
  List<GroupItem> _items = const [];
  bool _loading = true;
  String? _err;

  static const _tabs = [
    (view: 'join', name: '我參與的'),
    (view: 'manager', name: '我管理的'),
  ];

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
      final g = await api.fetchMyGroups(view: _view);
      if (mounted) setState(() => _items = g);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('我的群組'))),
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
                  for (final t in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(t.name)),
                        selected: _view == t.view,
                        onSelected: (_) {
                          setState(() => _view = t.view);
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
              emptyText: tr('還沒有加入任何群組'),
              onRetry: _load,
            ),
            if (_items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      ListTile(
                        leading: _items[i].icon.isEmpty
                            ? const Icon(LucideIcons.users)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: _items[i].icon,
                                  httpHeaders: Api.imageHeaders,
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                  errorWidget: (c, _, _) =>
                                      const Icon(LucideIcons.users),
                                ),
                              ),
                        title: Text(_items[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => context.push('/g/${_items[i].fid}'),
                      ),
                      if (i != _items.length - 1)
                        const Divider(height: 1, indent: 70, endIndent: 14),
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

/// 群組成員列表
class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({super.key, required this.fid, this.name = ''});
  final int fid;
  final String name;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  List<GroupMember> _items = const [];
  PageInfo _pager = const PageInfo();
  bool _loading = true;
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
      final r = await api.fetchGroupMembers(widget.fid, page: _page);
      if (mounted) {
        setState(() {
          _items = r.members;
          _pager = r.pager;
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.name.isEmpty ? tr('成員列表') : widget.name)),
      bottomNavigationBar: _items.isEmpty
          ? null
          : StickyPager(pager: _pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && _items.isEmpty,
              emptyText: tr('沒有成員'),
              onRetry: _load,
            ),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  children: [
                    for (final m in _items)
                      SizedBox(
                        width: 84,
                        child: InkWell(
                          onTap: m.uid == null
                              ? null
                              : () => context.push('/u/${m.uid}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              children: [
                                Avatar(m.avatar, size: 48),
                                const SizedBox(height: 5),
                                Text(m.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12)),
                                if (m.title.isNotEmpty)
                                  Text(m.title,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
