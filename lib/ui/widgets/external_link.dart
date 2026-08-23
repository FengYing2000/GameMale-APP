import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/ui.dart';
import '../../theme.dart';
import 'toast.dart';

/// 離開論壇前先問一聲。帖子裡常有網盤、短網址、廣告轉址，
/// 直接跳出去使用者根本不知道被帶去哪，所以把完整網址攤開來看。
Future<void> confirmExternal(
  BuildContext context,
  String url, {
  String? title,
  String? note,
}) async {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? url;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.open_in_new, size: 26),
      title: Text(title ?? tr('即將離開 GameMale')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(host,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(url,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: subtle(ctx))),
          ),
          const SizedBox(height: 10),
          Text(note ?? tr('這個連結不屬於論壇，請自行判斷是否安全。'),
              style: TextStyle(fontSize: 12, color: faint(ctx))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(ctx, false);
            toast(context, tr('已複製連結'));
          },
          child: Text(tr('複製連結')),
        ),
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(tr('前往'))),
      ],
    ),
  );

  if (go == true) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
