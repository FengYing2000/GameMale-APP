import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';

/// 用 App 內的 WebView 當論壇的傳輸層。
///
/// **為什麼需要**：論壇擋在 Cloudflare 後面時，光把解出來的 `cf_clearance`
/// 搬給 HTTP 客戶端**不夠**——實測還是 403。票是真的，但 Cloudflare 也看
/// TLS 指紋，拿票的必須真的是瀏覽器。
///
/// 所以連請求本身都交給 WebView：在論壇自己的頁面裡跑 `fetch()`，同源、
/// 自動帶齊所有 cookie（含 HttpOnly 的 `cf_clearance`），CF 看到的就是
/// 不折不扣的瀏覽器。回來的 HTML 再餵給原本那套解析器。
///
/// 只在 Cloudflare 擋著時才啟用——它比直連慢得多。
class BrowserFetch {
  BrowserFetch._();
  static final BrowserFetch instance = BrowserFetch._();

  static const _channel = 'GMBridge';

  /// 給宿主 widget 用：控制器建好之後才能把 WebView 掛上畫面
  final ready = ValueNotifier<WebViewController?>(null);

  Future<void>? _booting;
  final _pending = <int, Completer<String>>{};
  int _seq = 0;

  Future<void> _ensureReady() {
    if (ready.value != null) return Future.value();
    return _booting ??= _boot();
  }

  Future<void> _boot() async {
    // 先把 App 的 cookie 灌進去，WebView 開起來就是已登入狀態
    final jar = WebViewCookieManager();
    for (final cookie in await Api.instance.allCookies()) {
      await jar.setCookie(WebViewCookie(
        name: cookie.name,
        value: cookie.value,
        domain: Uri.parse(kForumOrigin).host,
      ));
    }

    final loaded = Completer<void>();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // UA 要跟 Api 一致：cookie 與 Cloudflare 的判斷都跟 UA 綁在一起
      ..setUserAgent(Api.userAgent)
      ..addJavaScriptChannel(_channel, onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onWebResourceError: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ));

    await c.loadRequest(Uri.parse('$kForumOrigin/forum.php?mobile=2'));
    ready.value = c; // 掛上畫面，JS 才跑得動（見 host()）

    // 等首頁載完，之後的 fetch 才落在論壇的同源環境裡。
    // Cloudflare 的挑戰頁也算「載完」——真瀏覽器通常會自己解掉。
    await loaded.future.timeout(const Duration(seconds: 45), onTimeout: () {});
  }

  void _onMessage(JavaScriptMessage m) {
    try {
      final data = json.decode(m.message) as Map<String, dynamic>;
      final c = _pending.remove(data['id'] as int);
      if (c == null || c.isCompleted) return;
      if (data['ok'] == true) {
        c.complete(data['body'] as String? ?? '');
      } else {
        c.completeError(DiscuzException('${data['error'] ?? '瀏覽器取得失敗'}'));
      }
    } catch (_) {
      // 壞掉的訊息就讓那個請求自己逾時，不要影響其他還在等的
    }
  }

  /// 用 WebView 抓一個網址。[form] 有值時送 POST（表單編碼，跟論壇一致）。
  Future<String> fetch(String url, {Map<String, String>? form}) async {
    await _ensureReady();
    final c = ready.value;
    if (c == null) throw const DiscuzException('瀏覽器傳輸沒有就緒');

    final id = ++_seq;
    final completer = Completer<String>();
    _pending[id] = completer;

    try {
      // 每次都重新注入：頁面一導覽 JS 環境就沒了，而挑戰頁本身就會導覽。
      // 這段很短，重覆執行的成本可以忽略。
      await c.runJavaScript(_injectedJs);
      await c.runJavaScript('window.__gmFetch(${json.encode({
            'id': id,
            'url': url,
            'form': form,
            'channel': _channel,
          })})');
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    final body = await completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pending.remove(id);
        throw const DiscuzException('瀏覽器取得逾時');
      },
    );

    // 這個隱形的 WebView 自己也可能被挑戰。拿回挑戰頁的 HTML 去餵解析器
    // 只會得到一片空白，所以要認出來、交給呼叫端去請使用者解一次。
    if (looksLikeChallenge(body)) throw const CloudflareException(_needSolve);
    return body;
  }

  static const _needSolve = '需要先通過論壇的安全驗證';

  /// 這段 HTML 是不是 Cloudflare 的挑戰頁。
  ///
  /// 走 WebView 時拿不到狀態碼與標頭（`fetch()` 只回文字），
  /// 只能比對挑戰頁的內文特徵。
  static bool looksLikeChallenge(String html) =>
      html.contains('cdn-cgi/challenge-platform') ||
      html.contains('cf-browser-verification') ||
      html.contains('_cf_chl_opt');

  static const _injectedJs = '''
window.__gmFetch = function (a) {
  var opt = { credentials: 'include', redirect: 'follow' };
  if (a.form) {
    opt.method = 'POST';
    opt.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    var b = new URLSearchParams();
    for (var k in a.form) { b.append(k, a.form[k]); }
    opt.body = b.toString();
  }
  fetch(a.url, opt)
    .then(function (r) { return r.text(); })
    .then(function (t) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: true, body: t }));
    })
    .catch(function (e) {
      window[a.channel].postMessage(
        JSON.stringify({ id: a.id, ok: false, error: String(e) }));
    });
};
''';

  /// 掛在畫面上的宿主。**必須真的在 widget 樹裡**——iOS 的 WKWebView
  /// 不在畫面上時 JavaScript 會被節流甚至完全不跑。
  ///
  /// 做成 1×1 而不是 0×0：有些版本對零尺寸的 WebView 根本不初始化。
  Widget host() => ValueListenableBuilder<WebViewController?>(
        valueListenable: ready,
        builder: (_, c, _) => c == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: WebViewWidget(controller: c),
                ),
              ),
      );
}
