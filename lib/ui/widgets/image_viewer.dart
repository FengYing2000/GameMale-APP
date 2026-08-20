import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/http.dart';

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
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: Api.imageHeaders,
                    fit: BoxFit.contain,
                    placeholder: (c, _) => const CircularProgressIndicator(strokeWidth: 2),
                    errorWidget: (c, _, _) =>
                        const Text('圖片載入失敗', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: const Text(
                '點一下關閉',
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
