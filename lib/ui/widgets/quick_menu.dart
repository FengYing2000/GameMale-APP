import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/http.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import 'avatar.dart';
import 'external_link.dart';

/// 論壇左側那排功能。這些是外掛頁面，沒有手機模板，
/// 用內建瀏覽器開（帶得到登入狀態）。
const _forumTools = <({String label, String icon, String path})>[
  (label: '勳章商城', icon: '🎖', path: 'wodexunzhang-showxunzhang.html'),
  (label: '我的勳章', icon: '▣', path: 'wodexunzhang-showxunzhang.html?action=my'),
  (label: '道具超市', icon: '㍰', path: 'home.php?mod=magic'),
  (label: '血液祭獻', icon: '⇄', path: 'plugin.php?id=k_xueyeji'),
  (label: '頭銜稱號', icon: 'Ｔ', path: 'home.php?mod=spacecp&ac=profile&op=base'),
  (label: '多彩名片', icon: '▤', path: 'k_usercard-style.html'),
  (label: '熱門任務', icon: '☑', path: 'home.php?mod=task'),
];

/// 首頁的側邊欄
class QuickDrawer extends StatelessWidget {
  const QuickDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .10),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  if (session.loggedIn && session.uid != null) {
                    context.push('/u/${session.uid}');
                  } else {
                    context.push('/login');
                  }
                },
                child: Row(
                  children: [
                    Avatar(session.avatar, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.loggedIn ? session.name : tr('尚未登入'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            session.loggedIn
                                ? 'UID ${session.uid}'
                                : tr('登入後才能簽到、發文、收藏'),
                            style: TextStyle(
                                fontSize: 12.5, color: faint(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _tile(context,
                icon: Icons.event_available_outlined,
                label: tr('每日簽到'),
                onTap: () => context.push('/sign')),
            _tile(context,
                icon: Icons.chat_bubble_outline,
                label: tr('記錄廣場'),
                onTap: () => context.push('/doing')),
            _tile(context,
                icon: Icons.groups_outlined,
                label: tr('群組'),
                onTap: () => context.push('/groups')),
            const Divider(height: 24, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('論壇功能'),
                  style: TextStyle(fontSize: 12, color: faint(context))),
            ),
            for (final t in _forumTools)
              _tile(context,
                  leading: Text(t.icon,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center),
                  label: tr(t.label),
                  onTap: () =>
                      openInApp(context, '$kOrigin/${t.path}', title: tr(t.label))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    IconData? icon,
    Widget? leading,
    required String label,
    required VoidCallback onTap,
  }) =>
      ListTile(
        dense: true,
        leading: SizedBox(
          width: 26,
          child: icon != null ? Icon(icon, size: 21) : leading,
        ),
        title: Text(label, style: const TextStyle(fontSize: 14.5)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
}
