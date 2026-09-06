import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:gm_api/http.dart';

import '../../services/browser_fetch_stub.dart'
    if (dart.library.io) '../../services/browser_fetch.dart';
import '../../services/transport_state.dart';

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

    // Cloudflare 擋著時，圖片也必須走 WebView。
    //
    // 圖片本來是 Flutter 自己的 HTTP 堆疊在抓（Image.network /
    // CachedNetworkImage），完全繞過傳輸層——所以會出現「文字讀得到、
    // 圖片整片載入失敗」：子版塊圖示、頭像、帖子裡的圖全都不見。
    // 網頁版：用瀏覽器原生載入（會跟 301 轉址，快取交給瀏覽器）
    if (kIsWeb) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: decodeW,
        cacheHeight: decodeW == null ? decodeH : null,
        // 冷啟動時瀏覽器快取命中就不會閃 placeholder，這裡只處理首次載入
        loadingBuilder: (c, child, progress) => progress == null ? child : ph,
        errorBuilder: (c, e, s) => err,
      );
    }

    // 原生版有兩條路，看 Cloudflare 有沒有擋著。
    //
    // **要監聽而不是只讀一次**：傳輸切換的瞬間所有圖片得一起重建，否則
    // App 剛啟動時先建好的那批（那時還沒撞到 403、走的是直連）會永遠停在
    // 載入失敗——實機症狀就是「文字讀得到、圖片全部載不出來」。
    return ValueListenableBuilder<bool>(
      valueListenable: usingBrowserTransport,
      builder: (_, viaBrowser, _) => viaBrowser
          ? _BrowserImage(
              url: url,
              width: width,
              height: height,
              fit: fit,
              placeholder: ph,
              errorWidget: err,
            )
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: Api.imageHeaders,
              width: width,
              height: height,
              fit: fit,
              memCacheWidth: decodeW,
              memCacheHeight: decodeW == null ? decodeH : null,
              placeholder: (c, _) => ph,
              errorWidget: (c, u, e) => err,
            ),
    );
  }
}

/// Cloudflare 擋著時用的圖片載入器：位元組由 WebView 取回來。
///
/// 自己記一份記憶體快取——同一張頭像在列表裡會出現很多次，每次都繞一趟
/// 瀏覽器＋base64 太貴。上限刻意設小，這只是被擋期間的過渡狀態。
class _BrowserImage extends StatefulWidget {
  const _BrowserImage({
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;

  static final _cache = <String, Uint8List>{};
  static const _maxEntries = 120;

  @override
  State<_BrowserImage> createState() => _BrowserImageState();
}

class _BrowserImageState extends State<_BrowserImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_BrowserImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final hit = _BrowserImage._cache[widget.url];
    if (hit != null) {
      setState(() => _bytes = hit);
      return;
    }
    try {
      final b = await BrowserFetch.instance.fetchBytes(widget.url);
      if (_BrowserImage._cache.length >= _BrowserImage._maxEntries) {
        _BrowserImage._cache.remove(_BrowserImage._cache.keys.first);
      }
      _BrowserImage._cache[widget.url] = b;
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.errorWidget;
    final b = _bytes;
    if (b == null) return widget.placeholder;
    return Image.memory(
      b,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (_, _, _) => widget.errorWidget,
    );
  }
}
