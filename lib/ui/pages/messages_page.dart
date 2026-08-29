import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
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


  int _rev = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 登入/登出後這個分頁還被保活著，靠 revision 判斷要不要重抓。
    // 第一次只記錄不重抓 —— initState 已經載過了，否則每次開頁都會抓兩遍
    final rev = context.watch<SessionStore>().revision;
    if (_rev == -1) {
      _rev = rev;
      return;
    }
    if (_rev != rev) {
      _rev = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

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
      if (mounted) {
        setState(() => _data = d);
        // 這份清單就是權威：還有沒有未讀，直接同步紅點
        context.read<SessionStore>()
            .setPmUnread(d.items.any((i) => i.unread > 0));
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 開對話：進去就等於讀過了，回來立刻把那一列的未讀數清掉並重抓清單，
  /// 不必等下次重開 App 紅點才消失。
  Future<void> _openChat(PmItem item) async {
    if (item.touid == null) return;
    await context.push(Uri(
      path: '/pm/${item.touid}',
      queryParameters: {'name': item.name},
    ).toString());
    if (!mounted) return;

    // 先本地清掉這一列的圈圈與紅點（伺服器已在檢視時標成已讀）
    final d = _data;
    if (d != null) {
      final items = [
        for (final x in d.items)
          x.touid == item.touid
              ? PmItem(
                  touid: x.touid,
                  name: x.name,
                  last: x.last,
                  time: x.time,
                  avatar: x.avatar,
                  unread: 0)
              : x,
      ];
      setState(() => _data = PmListResult(items: items, message: d.message));
      context.read<SessionStore>()
          .setPmUnread(items.any((i) => i.unread > 0));
    }
    // 再跟伺服器對一次（對方可能又回了新訊息）
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: Text(tr('訊息'))),
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
                  child: Icon(LucideIcons.bell,
                      color: Theme.of(context).colorScheme.primary),
                ),
                title: Text(tr('系統通知'), style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(tr('回覆、@我、積分等提醒'),
                    style: TextStyle(fontSize: 12.5, color: faint(context))),
                trailing: Icon(LucideIcons.chevronRight, color: faint(context)),
                onTap: () => context.push('/notice'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
              child: Text(tr('私人訊息'),
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: faint(context))),
            ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.items.isEmpty ?? false),
              emptyText: d?.message ?? tr('沒有私訊'),
              onRetry: _load,
            ),
            if (d != null && d.items.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < d.items.length; i++) ...[
                      _PmRow(
                        item: d.items[i],
                        onOpen: () => _openChat(d.items[i]),
                      ),
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
  const _PmRow({required this.item, required this.onOpen});
  final PmItem item;
  final VoidCallback onOpen;

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
      onTap: item.touid == null ? null : onOpen,
    );
  }
}
