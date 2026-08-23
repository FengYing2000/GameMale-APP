import 'package:flutter/material.dart';

/// 「本頁全部載入圖片」的開關。
///
/// 圖片是散在整篇內容裡的獨立 widget，各自記自己有沒有被點開；
/// 這個 scope 讓帖子頁能一次把整頁都打開，而不用去戳每一張。
class ImageReveal extends InheritedNotifier<ValueNotifier<bool>> {
  const ImageReveal({
    super.key,
    required ValueNotifier<bool> super.notifier,
    required super.child,
  });

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ImageReveal>()
          ?.notifier
          ?.value ??
      false;
}
