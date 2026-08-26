import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/http.dart';

/// 帖子裡的圖片有三種來源，各要不同的解碼路徑：
///
/// * 一般網址（jpg / png / gif）—— CachedNetworkImage
/// * `data:image/...;base64,` —— 內嵌在 HTML 裡，網路層根本拿不到，
///   要自己解 base64 丟給 Image.memory
/// * `.svg` —— 論壇的 emoji 走 jsdelivr 的 noto-emoji SVG，
///   Flutter 內建的解碼器不認得 SVG，要交給 flutter_svg
///
/// 少了後兩條就會整片顯示「圖片載入失敗」。
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.src,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String src;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  static bool isData(String src) => src.startsWith('data:');

  static bool isSvg(String src) =>
      src.toLowerCase().contains('.svg') || src.startsWith('data:image/svg');

  /// data: URI 的 base64 內容。解不出來就回 null，讓呼叫端顯示錯誤圖
  static Uint8List? decodeData(String src) {
    final comma = src.indexOf(',');
    if (comma < 0) return null;
    final meta = src.substring(0, comma);
    var body = src.substring(comma + 1);
    try {
      if (meta.contains(';base64')) {
        // HTML 裡常常夾了換行與空白，base64 解碼器不吃
        body = body.replaceAll(RegExp(r'\s'), '');
        return base64Decode(body);
      }
      return Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = errorWidget ??
        Icon(LucideIcons.imageOff,
            size: 22,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .4));

    if (isData(src)) {
      final bytes = decodeData(src);
      if (bytes == null) return fallback;
      if (isSvg(src)) {
        return SvgPicture.memory(bytes,
            width: width, height: height, fit: fit,
            placeholderBuilder: (_) => placeholder ?? const SizedBox.shrink());
      }
      return Image.memory(bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (c, _, _) => fallback);
    }

    if (isSvg(src)) {
      return SvgPicture.network(
        src,
        width: width,
        height: height,
        fit: fit,
        headers: Api.imageHeaders,
        placeholderBuilder: (_) => placeholder ?? const SizedBox.shrink(),
      );
    }

    return CachedNetworkImage(
      imageUrl: src,
      httpHeaders: Api.imageHeaders,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder == null ? null : (c, _) => placeholder!,
      errorWidget: (c, _, _) => fallback,
    );
  }
}
