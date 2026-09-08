import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
import '../../store/accounts.dart';
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
    (LucideIcons.star, '我的收藏', '/favorites', true),
    (LucideIcons.squarePen, '我的主題', '/my/thread', true),
    (LucideIcons.reply, '我的回覆', '/my/reply', true),
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

  /// 帳號切換入口。網頁版與沒有已存帳號時不顯示（accounts 在網頁版是空的）。
  Widget _accountSwitcher(BuildContext context) {
    final accounts = context.watch<AccountsStore>();
    if (accounts.accounts.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(LucideIcons.users, color: Theme.of(context).colorScheme.primary),
        title: Text(tr('切換帳號')),
        subtitle: Text(accounts.hasMultiple
            ? tr('已保存 ${accounts.accounts.length} 個帳號')
            : tr('新增其他帳號可快速切換')),
        trailing: const Icon(LucideIcons.chevronRight, size: 18),
        onTap: () => _showAccounts(context),
      ),
    );
  }

  void _showAccounts(BuildContext context) {
    final accounts = context.read<AccountsStore>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('帳號'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final a in accounts.accounts)
              ListTile(
                leading: Avatar(a.avatar, size: 40),
                title: Row(
                  children: [
                    Flexible(child: Text(a.name.isEmpty ? 'UID ${a.uid}' : a.name)),
                    if (a.uid == accounts.currentUid) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.check,
                          size: 16, color: Theme.of(context).colorScheme.primary),
                    ],
                  ],
                ),
                subtitle: Text('UID ${a.uid}'
                    '${a.remember ? ' · ${tr('已記住密碼')}' : ''}'),
                trailing: IconButton(
                  icon: Icon(LucideIcons.trash2, size: 18, color: faint(context)),
                  tooltip: tr('移除'),
                  onPressed: () => _confirmRemove(sheetCtx, a),
                ),
                onTap: a.uid == accounts.currentUid
                    ? null
                    : () async {
                        Navigator.pop(sheetCtx);
                        await accounts.switchTo(a.uid);
                        if (context.mounted) {
                          toast(context, tr('已切換到 ${a.name}'), kind: ToastKind.ok);
                        }
                      },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.plus),
              title: Text(tr('新增帳號')),
              onTap: () {
                Navigator.pop(sheetCtx);
                context.push('/login');
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext sheetCtx, Account a) async {
    final accounts = context.read<AccountsStore>();
    final ok = await showDialog<bool>(
      context: sheetCtx,
      builder: (c) => AlertDialog(
        title: Text(tr('移除帳號')),
        content: Text(tr('確定要從這台裝置移除「${a.name}」嗎？'
            '已記住的密碼也會一併刪除，論壇上的帳號不受影響。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('移除'))),
        ],
      ),
    );
    if (ok != true) return;
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
    await accounts.remove(a.uid);
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
            icon: const Icon(LucideIcons.settings),
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
                                // level 已經是完整的「Lvl. 7 ✓」，不要再加前綴
                                if (me?.level.isNotEmpty == true) me!.level,
                                if (session.sign?.title.isNotEmpty == true)
                                  session.sign!.title,
                              ].join(' · '),
                              style: TextStyle(fontSize: 12.5, color: faint(context)),
                            ),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, color: faint(context)),
                    ],
                  ),
                ),
              ),
            ),
            _accountSwitcher(context),
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
                            Icon(LucideIcons.chevronRight, size: 18, color: faint(context)),
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
