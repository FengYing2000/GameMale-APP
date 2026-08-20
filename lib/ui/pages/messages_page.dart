import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/state_box.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  PmListResult? _data;
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
      final d = await api.fetchPmList();
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
      appBar: AppBar(title: const Text('訊息')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                  child: Icon(Icons.notifications_none,
                      color: Theme.of(context).colorScheme.primary),
                ),
                title: const Text('系統通知', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('回覆、@我、積分等提醒',
                    style: TextStyle(fontSize: 12.5, color: faint(context))),
                trailing: Icon(Icons.chevron_right, color: faint(context)),
                onTap: () => context.push('/notice'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Text('私人訊息',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: faint(context))),
            ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.items.isEmpty ?? false),
              emptyText: d?.message ?? '沒有私訊',
              onRetry: _load,
            ),
            if (d != null && d.items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < d.items.length; i++) ...[
                      _PmRow(item: d.items[i]),
                      if (i != d.items.length - 1) const Divider(indent: 68, endIndent: 14),
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

class _PmRow extends StatelessWidget {
  const _PmRow({required this.item});
  final PmItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Avatar(item.avatar, size: 40),
      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: item.last.isEmpty
          ? null
          : Text(item.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: faint(context))),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (item.time.isNotEmpty)
            Text(item.time, style: TextStyle(fontSize: 11.5, color: faint(context))),
          if (item.unread > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: const BoxDecoration(
                color: Color(0xFFD93025),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text('${item.unread}',
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ),
          ],
        ],
      ),
      onTap: item.touid == null ? null : () => context.push('/pm/${item.touid}'),
    );
  }
}
