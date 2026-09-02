import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 原生版：把 CachedNetworkImage 快取到的暫存目錄大小加總。
Future<int?> diskCacheBytes() async {
  try {
    final tmp = await getTemporaryDirectory();
    var total = 0;
    // flutter_cache_manager 預設把圖片放這個資料夾
    final dir = Directory('${tmp.path}/libCachedImageData');
    if (await dir.exists()) {
      await for (final f in dir.list(recursive: true)) {
        if (f is File) total += await f.length();
      }
    }
    return total;
  } catch (_) {
    return null;
  }
}
