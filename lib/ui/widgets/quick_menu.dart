import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import 'avatar.dart';

/// 論壇左側那排功能。原本全是只有桌面模板的外掛頁面，現在都做成原生頁；
/// [path] 是 App 內的路由，各頁右上角還留著「在網頁開啟」可以退回論壇原頁。
const forumTools = <({String id, String label, IconData icon, String path})>[
  (id: 'medalshop', label: '勳章商城', icon: LucideIcons.medal, path: '/tools/medal'),
  (id: 'mymedal', label: '我的勳章', icon: LucideIcons.award, path: '/tools/medal?tab=mine'),
  (id: 'magic', label: '道具超市', icon: LucideIcons.wand, path: '/tools/magic'),
  (id: 'blood', label: '血液祭獻', icon: LucideIcons.droplet, path: '/tools/blood'),
  (id: 'card', label: '日常卡片', icon: LucideIcons.creditCard, path: '/tools/card'),
  (id: 'buyname', label: '頭銜稱號', icon: LucideIcons.tag, path: '/tools/title'),
  (id: 'usercard', label: '多彩名片', icon: LucideIcons.idCard, path: '/tools/usercard'),
  (id: 'bgshop', label: '背景商店', icon: LucideIcons.image, path: '/tools/bg'),
  (id: 'draw', label: '你畫我猜', icon: LucideIcons.pencil, path: '/tools/draw'),
  (id: 'task', label: '熱門任務', icon: LucideIcons.listChecks, path: '/tools/task'),
  (id: 'posttask', label: '每週發帖獎勵', icon: LucideIcons.squarePen, path: '/tools/task/25?title=%E6%AF%8F%E9%80%B1%E7%99%BC%E5%B8%96%E7%8D%8E%E5%8B%B5'),
  (id: 'replytask', label: '每月回帖獎勵', icon: LucideIcons.reply, path: '/tools/reply-reward'),
];

/// 首頁的側邊欄
class QuickDrawer extends StatelessWidget {
  const QuickDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final settings = context.watch<SettingsStore>();
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
                icon: LucideIcons.calendarCheck,
                label: tr('每日簽到'),
                onTap: () => context.push('/sign')),
            _tile(context,
                icon: LucideIcons.messageCircle,
                label: tr('記錄廣場'),
                onTap: () => context.push('/doing')),
            _tile(context,
                icon: LucideIcons.fileText,
                label: tr('日誌'),
                onTap: () => context.push('/blogs')),
            _tile(context,
                icon: LucideIcons.library,
                label: tr('淘帖'),
                onTap: () => context.push('/collections')),
            _tile(context,
                icon: LucideIcons.users,
                label: tr('群組'),
                onTap: () => context.push('/groups')),
            const Divider(height: 24, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Text(tr('論壇功能'),
                      style: TextStyle(fontSize: 12, color: faint(context))),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/settings/tools');
                    },
                    icon: const Icon(LucideIcons.slidersHorizontal, size: 15),
                    label: Text(tr('編排')),
                  ),
                ],
              ),
            ),
            for (final t in settings.visibleTools)
              _tile(context,
                  icon: t.icon,
                  label: tr(t.label),
                  onTap: () {
                    Navigator.pop(context);
                    context.push(t.path);
                  }),
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
