import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/toast.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  MeData? _me;

  static const _entries = [
    (Icons.star_outline, '我的收藏', '/my/favorite'),
    (Icons.edit_note, '我的主題', '/my/thread'),
    (Icons.reply_outlined, '我的回覆', '/my/reply'),
    (Icons.event_available_outlined, '每日簽到', '/sign'),
    (Icons.chat_bubble_outline, '記錄廣場', '/doing'),
    (Icons.notifications_none, '系統通知', '/notice'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<SessionStore>().uid;
    if (uid == null) return;
    try {
      final m = await api.fetchMe(uid);
      if (mounted) setState(() => _me = m);
    } on DiscuzException {
      // 顯示本機快取的資料即可
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('登出')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SessionStore>().signOut();
    if (mounted) toast(context, '已登出');
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final me = _me;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: session.uid == null ? null : () => context.push('/u/${session.uid}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    children: [
                      Avatar(session.avatar, size: 60),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me?.name.isNotEmpty == true
                                  ? me!.name
                                  : (session.name.isEmpty ? '未登入' : session.name),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                'UID ${session.uid ?? '—'}',
                                if (me?.level.isNotEmpty == true) 'Lv.${me!.level}',
                                if (session.sign?.title.isNotEmpty == true)
                                  session.sign!.title,
                              ].join(' · '),
                              style: TextStyle(fontSize: 12.5, color: faint(context)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: faint(context)),
                    ],
                  ),
                ),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _entries.length; i++) ...[
                    ListTile(
                      leading: Icon(_entries[i].$1, size: 22),
                      title: Text(_entries[i].$2),
                      trailing: Icon(Icons.chevron_right, size: 18, color: faint(context)),
                      onTap: () => context.push(_entries[i].$3),
                    ),
                    if (i != _entries.length - 1) const Divider(indent: 56, endIndent: 14),
                  ],
                ],
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Center(
                  child: Text('登出',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                onTap: _signOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
