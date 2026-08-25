import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/http.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import 'avatar.dart';
import 'external_link.dart';

/// 論壇左側那排功能。這些是外掛頁面，沒有手機模板，
/// 用內建瀏覽器開（帶得到登入狀態）。
/// 論壇左側那排功能。全都是外掛頁面，只有桌面模板，
/// 用內建瀏覽器開（帶得到登入狀態，網址也會補上 mobile=no）。
const forumTools = <({String id, String label, String icon, String path})>[
  (id: 'medalshop', label: '勳章商城', icon: '🎖', path: 'wodexunzhang-showxunzhang.html'),
  (id: 'mymedal', label: '我的勳章', icon: '▣', path: 'wodexunzhang-showxunzhang.html?action=my'),
  (id: 'magic', label: '道具超市', icon: '㍰', path: 'home.php?mod=magic'),
  (id: 'blood', label: '血液祭獻', icon: '⇄', path: 'home.php?mod=spacecp&ac=credit&op=exchange'),
  (id: 'card', label: '日常卡片', icon: '¼', path: 'it618_award-award.html'),
  (id: 'buyname', label: '頭銜稱號', icon: 'Ｔ', path: 'tshuz_buyname-tshuz_buyname.html'),
  (id: 'usercard', label: '多彩名片', icon: '▤', path: 'k_usercard-style.html'),
  (id: 'bgshop', label: '背景商店', icon: 'Ｂ', path: 'tshuz_bgshop-tshuz_bgshop.html'),
  (id: 'draw', label: '你畫我猜', icon: '✎', path: 'plugin.php?id=viewui_draw'),
  (id: 'task', label: '熱門任務', icon: '☑', path: 'home.php?mod=task'),
  (id: 'signtask', label: '每日簽到任務', icon: '✓', path: 'k_misign-sign.html'),
  (id: 'posttask', label: '每週發帖獎勵', icon: '✎', path: 'home.php?mod=task&do=view&id=25'),
  (id: 'replytask', label: '每月回帖獎勵', icon: '↩', path: 'reply_reward-reply_reward.html'),
  (id: 'survey', label: '科考小隊', icon: '⚑', path: 'nds_up_ques-nds_up_ques.html'),
  (id: 'newblog', label: '最新日誌', icon: '✦', path: 'home.php?mod=space&uid=617370&do=blog&classid=1293&view=me'),
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
                    icon: const Icon(Icons.tune, size: 15),
                    label: Text(tr('編排')),
                  ),
                ],
              ),
            ),
            for (final t in settings.visibleTools)
              _tile(context,
                  leading: Text(t.icon,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center),
                  label: tr(t.label),
                  onTap: () => openInApp(
                      context, Api.desktopFullUrl(t.path),
                      title: tr(t.label))),
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
