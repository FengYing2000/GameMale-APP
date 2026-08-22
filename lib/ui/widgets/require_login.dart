import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../i18n/ui.dart';
import '../../store/session.dart';

/// 需要登入的操作在動手前先攔一次。
///
/// 論壇端會擋，但擋下來的回應長得像正常頁面，使用者會以為送出成功了。
/// 在這裡先問清楚，順便給一個直接去登入的入口。
Future<bool> requireLogin(BuildContext context, {String? action}) async {
  if (context.read<SessionStore>().loggedIn) return true;

  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('需要登入')),
      content: Text(action == null
          ? tr('這個操作需要先登入論壇帳號。')
          : '${tr('要')}$action${tr('需要先登入論壇帳號。')}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('前往登入'))),
      ],
    ),
  );
  if (go == true && context.mounted) context.push('/login');
  return false;
}
