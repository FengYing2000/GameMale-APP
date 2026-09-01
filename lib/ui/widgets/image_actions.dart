import '../../i18n/ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gm_api/http.dart';
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
            leading: const Icon(LucideIcons.download),
            title: Text(tr('儲存到相簿')),
            onTap: () {
              Navigator.pop(sheet);
              _save(context, url);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.share),
            title: Text(tr('分享')),
            onTap: () {
              Navigator.pop(sheet);
              SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.link),
            title: Text(tr('複製原始連結')),
            onTap: () async {
              Navigator.pop(sheet);
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) toast(context, tr('已複製連結'));
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.externalLink),
            title: Text(tr('用瀏覽器開啟')),
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
  // 網頁版沒辦法用程式把圖片寫進相簿（瀏覽器不給），
  // 只能請使用者長按圖片自己存。這是 PWA 相對原生 App 唯一少掉的功能。
  if (kIsWeb) {
    toast(context, tr('網頁版請長按圖片，選「儲存影像」'));
    return;
  }
  try {
    if (!await Gal.hasAccess(toAlbum: true)) {
      if (!await Gal.requestAccess(toAlbum: true)) {
        if (context.mounted) toast(context, tr('沒有相簿權限，請到系統設定開啟'));
        return;
      }
    }
    // 圖片可能來自外站圖床，走同一組標頭比較不會被擋
    await Gal.putImageBytes(
      await Api.instance.getAbsoluteBytes(url),
      album: 'GameMale',
    );
    if (context.mounted) toast(context, tr('已儲存到相簿'));
  } on GalException catch (e) {
    if (context.mounted) toast(context, tr('儲存失敗：${e.type.message}'));
  } catch (e) {
    if (context.mounted) toast(context, tr('儲存失敗：$e'));
  }
}
