import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 網頁版沒有內嵌 WebView（它本身就在瀏覽器裡），而且就算有也沒用：
/// 它的請求是從伺服器發出的，Cloudflare 的通行證綁的是解題那台機器的 IP。
/// 留一份同介面的空殼讓條件式 import 編得過。
class BrowserFetch {
  BrowserFetch._();
  static final BrowserFetch instance = BrowserFetch._();

  Future<String> fetch(String url, {Map<String, String>? form}) async =>
      throw UnsupportedError('網頁版沒有瀏覽器傳輸');

  void warmUp() {}

  final presenting = ValueNotifier<bool>(false);
  WebViewController? get controller => null;
  void restoreDelegate() {}

  Future<Uint8List> fetchBytes(String url) async =>
      throw UnsupportedError('網頁版沒有瀏覽器傳輸');

  Widget host() => const SizedBox.shrink();
}
