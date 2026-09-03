import 'package:flutter/painting.dart';

/// 網頁版：圖片的持久快取是瀏覽器的 HTTP 快取，Dart 量不到。
/// 能量的是 Flutter 自己在記憶體裡那份**已解碼**的圖片快取——
/// 那也是佔記憶體最兇、清掉最有感的一份。
Future<int?> diskCacheBytes() async =>
    PaintingBinding.instance.imageCache.currentSizeBytes;
