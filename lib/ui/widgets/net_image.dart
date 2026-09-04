import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:gm_api/http.dart';

/// 論壇圖片的載入器，一套介面兩種實作。
///
/// * **原生版**用 `CachedNetworkImage`：會把圖片快取到磁碟，冷啟動不用重抓。
/// * **網頁版**用 `Image.network`（瀏覽器原生的 <img>）。原因是論壇有些圖是
///   會 301 轉址的端點（頭像的 `avatar.php`、附件的 `attachment.php`），
///   `CachedNetworkImage` 在網頁上對這種會轉址的圖載不出來，而 <img> 一定
///   會跟轉址，快取也交給瀏覽器自己管，可靠得多。
///
/// 兩邊都不帶自訂標頭：瀏覽器禁止自訂 User-Agent/Referer（會讓請求直接
/// 失敗），而網頁版的圖本來就走同源的 /gm 代理，標頭由伺服器補。
class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const SizedBox.shrink();
    final err = errorWidget ?? ph;
    if (url.isEmpty) return err;

    // 只解碼到實際要畫的大小。
    //
    // 論壇的頭像原圖可能是 200×200 以上，而列表裡只畫 40px；照原尺寸解碼
    // 等於每張多花十幾倍的記憶體與時間，捲動時 CanvasKit 還要把那些過大的
    // 貼圖全部傳給 GPU。一頁二十幾個頭像的差距很有感。
    //
    // 乘上螢幕的像素密度，否則高解析度螢幕上會糊掉。
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final decodeW = width == null ? null : (width! * dpr).round();
    final decodeH = height == null ? null : (height! * dpr).round();

    if (kIsWeb) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: decodeW,
        cacheHeight: decodeW == null ? decodeH : null,
        // 冷啟動時瀏覽器快取命中就不會閃 placeholder，這裡只處理首次載入
        loadingBuilder: (c, child, progress) =>
            progress == null ? child : ph,
        errorBuilder: (c, e, s) => err,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: Api.imageHeaders,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decodeW,
      memCacheHeight: decodeW == null ? decodeH : null,
      placeholder: (c, _) => ph,
      errorWidget: (c, u, e) => err,
    );
  }
}
