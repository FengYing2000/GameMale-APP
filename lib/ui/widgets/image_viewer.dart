import '../../i18n/ui.dart';
import 'package:flutter/material.dart';

import 'image_actions.dart';
import 'smart_image.dart';

/// 全螢幕看圖，支援雙指縮放與拖曳
void showImageViewer(BuildContext context, String url) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => _Viewer(url: url),
  ));
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onLongPress: () => showImageActions(context, url),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: SmartImage(
                    src: url,
                    fit: BoxFit.contain,
                    placeholder: const CircularProgressIndicator(strokeWidth: 2),
                    errorWidget: Text(tr('圖片載入失敗'),
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: Text(
                tr('點一下關閉 · 長按更多'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
