import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/ui.dart';
import '../../theme.dart';

/// 論壇把需要登入的板塊/帖子直接 302 轉到登入頁，
/// 跟隨轉址後解析到的是登入表單，若照一般流程處理會顯示成「沒有內容」。
class LoginRequired extends StatelessWidget {
  const LoginRequired({super.key, this.message});

  /// 論壇給的說明，沒有就用預設文案
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 70, 32, 40),
      child: Column(
        children: [
          Icon(LucideIcons.lock, size: 40, color: faint(context)),
          const SizedBox(height: 14),
          Text(
            tr('需要登入才能查看'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message ?? tr('這個板塊只開放給已登入的會員。'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: subtle(context)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/login'),
            icon: const Icon(LucideIcons.logIn, size: 18),
            label: Text(tr('前往登入')),
          ),
        ],
      ),
    );
  }
}
