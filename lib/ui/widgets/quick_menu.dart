import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/http.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import 'avatar.dart';
import 'external_link.dart';

/// 論壇左側那排功能。有原生頁的走 App，其餘（勳章商城、道具超市…）
/// 是外掛頁面，沒有手機模板，交給瀏覽器。
const _forumTools = <({String label, String icon, String path, bool external})>[
  (label: '勳章商城', icon: '🎖', path: 'wodexunzhang-showxunzhang.html', external: true),
  (label: '我的勳章', icon: '▣', path: 'wodexunzhang-showxunzhang.html?action=my', external: true),
  (label: '道具超市', icon: '㍰', path: 'home.php?mod=magic', external: true),
  (label: '血液祭獻', icon: '⇄', path: 'plugin.php?id=k_xueyeji', external: true),
  (label: '頭銜稱號', icon: 'T', path: 'home.php?mod=spacecp&ac=profile&op=base', external: true),
  (label: '多彩名片', icon: '▤', path: 'k_usercard-style.html', external: true),
  (label: '熱門任務', icon: '☑', path: 'home.php?mod=task', external: true),
  (label: '論壇規範', icon: '★', path: 'thread-104691-1-1.html', external: false),
];

/// 首頁右上角頭像的功能選單
Future<void> showQuickMenu(BuildContext context) {
  final session = context.read<SessionStore>();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Avatar(session.avatar, size: 42),
              title: Text(
                session.loggedIn ? session.name : tr('尚未登入'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                session.loggedIn ? 'UID ${session.uid}' : tr('登入後才能簽到、發文、收藏'),
                style: TextStyle(fontSize: 12.5, color: faint(c)),
              ),
              onTap: () {
                Navigator.pop(c);
                if (session.loggedIn && session.uid != null) {
                  context.push('/u/${session.uid}');
                } else {
                  context.push('/login');
                }
              },
            ),
            const Divider(height: 1),
            _grid(c, [
              (label: '每日簽到', icon: Icons.event_available_outlined, path: '/sign'),
              (label: '系統通知', icon: Icons.notifications_none, path: '/notice'),
              (label: '記錄廣場', icon: Icons.chat_bubble_outline, path: '/doing'),
              (label: '我的收藏', icon: Icons.star_outline, path: '/my/favorite'),
              (label: '我的主題', icon: Icons.edit_note, path: '/my/thread'),
              (label: '我的回覆', icon: Icons.reply_outlined, path: '/my/reply'),
              (label: '私訊', icon: Icons.mail_outline, path: '/messages'),
              (label: '設定', icon: Icons.settings_outlined, path: '/settings'),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(tr('論壇功能'),
                  style: TextStyle(fontSize: 12, color: faint(c))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _forumTools)
                    ActionChip(
                      avatar: Text(t.icon, style: const TextStyle(fontSize: 13)),
                      label: Text(tr(t.label),
                          style: const TextStyle(fontSize: 13)),
                      onPressed: () {
                        Navigator.pop(c);
                        confirmExternal(
                          context,
                          '$kOrigin/${t.path}',
                          title: tr('用瀏覽器開啟'),
                          note: tr('這是論壇的外掛頁面，沒有手機版模板，'
                              'App 內顯示會跑版，所以交給瀏覽器。'),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _grid(
  BuildContext c,
  List<({String label, IconData icon, String path})> items,
) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: .95,
        children: [
          for (final i in items)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.pop(c);
                c.push(i.path);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(i.icon, size: 23),
                  const SizedBox(height: 7),
                  Text(tr(i.label), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
