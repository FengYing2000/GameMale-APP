import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/group.dart' as api;
import '../../api/http.dart';
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../widgets/state_box.dart';

/// 群組列表
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  List<GroupItem> _items = const [];
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
      final g = await api.fetchGroups();
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
      appBar: AppBar(title: Text(tr('群組'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && _items.isEmpty,
              emptyText: tr('沒有群組'),
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
                            ? const Icon(Icons.groups_outlined)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: _items[i].icon,
                                  httpHeaders: Api.imageHeaders,
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                  errorWidget: (c, _, _) =>
                                      const Icon(Icons.groups_outlined),
                                ),
                              ),
                        title: Text(_items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5)),
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
