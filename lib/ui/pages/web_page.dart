import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/http.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';

/// App 內建的瀏覽器。
///
/// 論壇有一堆外掛頁面沒有手機模板（勳章商城、附件購買、群組…），
/// 丟給系統瀏覽器的話那邊沒有登入狀態，等於要再登入一次。
/// 這裡把 App 的 cookie 灌進 WebView，開起來就是已登入的頁面。
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url, this.title = ''});
  final String url;
  final String title;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? _controller;
  int _progress = 0;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _boot();
  }

  Future<void> _boot() async {
    final jar = WebViewCookieManager();
    for (final c in await Api.instance.allCookies()) {
      await jar.setCookie(WebViewCookie(
        name: c.name,
        value: c.value,
        domain: Uri.parse(kOrigin).host,
      ));
    }
    if (!mounted) return;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(Api.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (_) async {
          final t = await _controller?.getTitle();
          if (mounted && t != null && t.isNotEmpty) {
            setState(() => _title = t.split(' - ').first);
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));

    setState(() => _controller = controller);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title.isEmpty ? tr('論壇頁面') : _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                    value: _progress / 100, minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            tooltip: tr('重新整理'),
            icon: const Icon(Icons.refresh),
            onPressed: () => c?.reload(),
          ),
          IconButton(
            tooltip: tr('用系統瀏覽器開啟'),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.parse(widget.url),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: c),
      bottomNavigationBar: c == null
          ? null
          : SafeArea(
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      onPressed: () async {
                        if (await c.canGoBack()) await c.goBack();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 18),
                      onPressed: () async {
                        if (await c.canGoForward()) await c.goForward();
                      },
                    ),
                    Expanded(
                      child: Text(
                        Uri.parse(widget.url).host,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: faint(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
