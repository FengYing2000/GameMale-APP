import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/group.dart' as api;
import '../../api/http.dart';
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/external_link.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';

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
      ),
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
                            const Icon(Icons.groups_outlined),
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
                        if (d.meta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(d.meta,
                              style: TextStyle(
                                  fontSize: 12, color: faint(context))),
                        ],
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
            ],
          ),
        ),
      );

  Widget _empty(GroupData d) => Padding(
        padding: const EdgeInsets.fromLTRB(36, 40, 36, 20),
        child: Column(
          children: [
            Icon(d.needsLogin ? Icons.lock_outline : Icons.groups_outlined,
                size: 34, color: faint(context)),
            const SizedBox(height: 14),
            Text(
              d.message ?? tr('這個群組沒有主題'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.7),
            ),
            const SizedBox(height: 18),
            // 加入與申請都得在論壇頁面上完成
            FilledButton.icon(
              onPressed: () => openInApp(
                context,
                '$kOrigin/group-${widget.fid}-1.html',
                title: d.name,
              ),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: Text(tr('在論壇頁面開啟')),
            ),
          ],
        ),
      );
}
