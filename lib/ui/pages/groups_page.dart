import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/group.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/state_box.dart';

/// 群組首頁：推薦群組、群組分類、積分排行
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  GroupIndex? _data;
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
      final g = await api.fetchGroupIndex();
      if (mounted) setState(() => _data = g);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('群組')),
        actions: [
          if (context.watch<SessionStore>().loggedIn)
            TextButton.icon(
              onPressed: () => context.push('/groups/my'),
              icon: const Icon(LucideIcons.userCheck, size: 16),
              label: Text(tr('我參與的')),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              if (d.recommended.isNotEmpty) ...[
                _header(context, tr('推薦群組')),
                for (final g in d.recommended) _RecommendCard(item: g),
              ],
              if (d.ranking.isNotEmpty) ...[
                _header(context, tr('積分排行')),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final r in d.ranking)
                        ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: 26,
                            child: Text('${r.rank}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: r.rank <= 3
                                        ? Theme.of(context).colorScheme.primary
                                        : faint(context))),
                          ),
                          title: Text(r.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(r.points,
                              style: TextStyle(
                                  fontSize: 12.5, color: subtle(context))),
                          onTap: () => context.push('/g/${r.fid}'),
                        ),
                    ],
                  ),
                ),
              ],
              for (final c in d.categories) _CategoryBlock(cat: c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: faint(c))),
      );
}

class _RecommendCard extends StatelessWidget {
  const _RecommendCard({required this.item});
  final GroupItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/g/${item.fid}'),
        leading: item.icon.isEmpty
            ? const Icon(LucideIcons.users, size: 34)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: item.icon,
                  httpHeaders: Api.imageHeaders,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (c, _, _) => const Icon(LucideIcons.users),
                ),
              ),
        title: Text(item.name,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: item.desc.isEmpty
            ? null
            : Text(item.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.4)),
        trailing: const Icon(LucideIcons.chevronRight, size: 18),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.cat});
  final GroupCategory cat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
          child: Row(
            children: [
              Text(cat.name,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: faint(context))),
              if (cat.count.isNotEmpty)
                Text('　${cat.count}',
                    style: TextStyle(fontSize: 11.5, color: faint(context))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in cat.groups)
                ActionChip(
                  label: Text(g.name, style: const TextStyle(fontSize: 13)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push('/g/${g.fid}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
