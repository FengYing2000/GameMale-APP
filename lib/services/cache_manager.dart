import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/painting.dart';

import 'cache_size_io.dart' if (dart.library.js_interop) 'cache_size_web.dart';

/// 圖片快取管理。
///
/// 網頁版的持久快取是瀏覽器的 HTTP 快取，Dart 量不到也清不動（那是瀏覽器
/// 的權責）；能清的是 Flutter 記憶體裡那份解碼快取，以及原生的磁碟快取。

/// 目前快取大小（bytes）。
/// 原生版是磁碟上的圖片快取；網頁版是記憶體裡已解碼的圖片快取
/// （持久快取由瀏覽器管，Dart 量不到）。
Future<int?> cacheSizeBytes() => diskCacheBytes();

/// 清掉能清的所有圖片快取。
Future<void> clearImageCache() async {
  // Flutter 記憶體裡的解碼快取（兩個平台都有）
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  // CachedNetworkImage 的磁碟快取（原生）
  await DefaultCacheManager().emptyCache();
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
