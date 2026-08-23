import '../../i18n/ui.dart';
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

  // needsLogin=false 的訪客也能看，論壇本來就開放
  static const _entries = [
    (Icons.star_outline, '我的收藏', '/my/favorite', true),
    (Icons.edit_note, '我的主題', '/my/thread', true),
    (Icons.reply_outlined, '我的回覆', '/my/reply', true),
    (Icons.event_available_outlined, '每日簽到', '/sign', true),
    (Icons.chat_bubble_outline, '記錄廣場', '/doing', false),
    (Icons.notifications_none, '系統通知', '/notice', true),
  ];


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
    final uid = context.read<SessionStore>().uid;
    // 登出後一定要把舊資料清掉 —— 只是 return 的話畫面會一直留著
    // 上一個帳號的名字與等級，直到重開 App
    if (uid == null) {
      if (_me != null && mounted) setState(() => _me = null);
      return;
    }
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
        title: Text(tr('登出')),
        content: Text(tr('確定要登出嗎？')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('登出'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SessionStore>().signOut();
    if (mounted) toast(context, tr('已登出'));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final me = _me;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('我的')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr('設定'),
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
                                  : (session.name.isEmpty ? tr('未登入') : session.name),
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
            Builder(builder: (context) {
              final items = _entries
                  .where((e) => session.loggedIn || !e.$4)
                  .toList();
              if (items.isEmpty) return const SizedBox.shrink();
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      ListTile(
                        leading: Icon(items[i].$1, size: 22),
                        title: Text(tr(items[i].$2)),
                        trailing:
                            Icon(Icons.chevron_right, size: 18, color: faint(context)),
                        onTap: () => context.push(items[i].$3),
                      ),
                      if (i != items.length - 1)
                        const Divider(indent: 56, endIndent: 14),
                    ],
                  ],
                ),
              );
            }),
            Card(
              clipBehavior: Clip.antiAlias,
              child: session.loggedIn
                  ? ListTile(
                      title: Center(
                        child: Text(tr('登出'),
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                      onTap: _signOut,
                    )
                  : ListTile(
                      title: Center(
                        child: Text(tr('登入'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                      onTap: () => context.push('/login'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
