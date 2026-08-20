import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import 'toast.dart';

/// 長按圖片時的動作選單
Future<void> showImageActions(BuildContext context, String url) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(sheet).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('儲存到相簿'),
            onTap: () {
              Navigator.pop(sheet);
              _save(context, url);
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('分享'),
            onTap: () {
              Navigator.pop(sheet);
              SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('複製原始連結'),
            onTap: () async {
              Navigator.pop(sheet);
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) toast(context, '已複製連結');
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('用瀏覽器開啟'),
            onTap: () {
              Navigator.pop(sheet);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _save(BuildContext context, String url) async {
  try {
    if (!await Gal.hasAccess(toAlbum: true)) {
      if (!await Gal.requestAccess(toAlbum: true)) {
        if (context.mounted) toast(context, '沒有相簿權限，請到系統設定開啟');
        return;
      }
    }
    // 圖片可能來自外站圖床，走同一組標頭比較不會被擋
    await Gal.putImageBytes(
      await Api.instance.getAbsoluteBytes(url),
      album: 'GameMale',
    );
    if (context.mounted) toast(context, '已儲存到相簿');
  } on GalException catch (e) {
    if (context.mounted) toast(context, '儲存失敗：${e.type.message}');
  } catch (e) {
    if (context.mounted) toast(context, '儲存失敗：$e');
  }
}
