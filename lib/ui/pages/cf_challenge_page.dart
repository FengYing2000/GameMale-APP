import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gm_api/http.dart';

import '../../i18n/ui.dart';
import '../../theme.dart';

/// 論壇的 Cloudflare 安全驗證。
///
/// **為什麼一定要用 WebView**：Cloudflare 的挑戰要真的執行 JavaScript
/// 才解得開，App 用的 HTTP 客戶端做不到——它只會一直拿到 403。
/// 解開之後 Cloudflare 會發一個 `cf_clearance` cookie，把它拿回來灌進
/// App 的連線，後面的請求就過得去了。
///
/// **UA 必須跟 App 一致**（`Api.userAgent`）：`cf_clearance` 綁 IP ＋
/// User-Agent，WebView 用預設 UA 解出來的那張票，App 拿去用不算數。
///
/// 這只在原生版有意義。網頁版的請求是從伺服器發出的，而票綁的是**解題那台
/// 機器的 IP**，使用者在自己瀏覽器上解的拿到伺服器上沒用。
class CfChallengePage extends StatefulWidget {
  const CfChallengePage({super.key});

  @override
  State<CfChallengePage> createState() => _CfChallengePageState();
}

class _CfChallengePageState extends State<CfChallengePage> {
  WebViewController? _controller;
  bool _done = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final jar = WebViewCookieManager();
    // 先把現有的登入 cookie 灌進去，免得驗證完變成未登入狀態
    for (final c in await Api.instance.allCookies()) {
      await jar.setCookie(
        WebViewCookie(
          name: c.name,
          value: c.value,
          domain: Uri.parse(kForumOrigin).host,
        ),
      );
    }
    if (!mounted) return;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ⚠️ 一定要跟 Api 用同一個 UA，見類別說明
      ..setUserAgent(Api.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _check()),
      )
      ..loadRequest(Uri.parse('$kForumOrigin/forum.php?mobile=2'));

    setState(() => _controller = controller);
  }

  /// 判斷「解開了沒」要看**畫面上真的是論壇了**，不能看 cookie 存不存在。
  ///
  /// 踩過這個坑：上一次解出來的 `cf_clearance` 還留在 cookie store 裡，
  /// 於是這頁一打開就以為已經成功、立刻自己關掉——使用者看到的是驗證頁
  /// 一閃而過，然後什麼都沒解決。票還在不代表它還有效。
  static const _probeJs = '''
(function () {
  var h = document.documentElement ? document.documentElement.innerHTML : '';
  if (h.indexOf('challenge-platform') >= 0 || h.indexOf('_cf_chl_opt') >= 0) {
    return 'challenge';
  }
  return document.querySelector('#hd, #nv, .bm, #ft, #postlist') ? 'forum' : 'other';
})()
''';

  Future<void> _check({bool manual = false}) async {
    if (_done || _checking) return;
    final c = _controller;
    if (c == null) return;
    _checking = true;
    try {
      if (!manual) {
        final r = await c.runJavaScriptReturningResult(_probeJs);
        // 平台之間回傳格式不一致（有的帶引號），統一拆掉再比
        if (r.toString().replaceAll('"', '') != 'forum') return;
      }
      await _harvest();
      _done = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // 探測失敗就讓使用者自己按「我已完成」，不要卡在這頁
    } finally {
      _checking = false;
    }
  }

  /// 順手把 cookie 撈回 App。
  ///
  /// 主要的通行還是靠 WebView 自己發請求（見 `services/browser_fetch.dart`），
  /// 但論壇解除驗證後會切回直連，那時這份 cookie 就派得上用場。
  ///
  /// `cf_clearance` 是 HttpOnly，`document.cookie` 讀不到，只能走平台的
  /// cookie store —— `WebViewCookieManager.getCookies` 兩邊都通。
  Future<void> _harvest() async {
    try {
      final cookies = await WebViewCookieManager().getCookies(
        domain: Uri.parse(kForumOrigin),
      );
      if (cookies.isEmpty) return;
      await Api.instance.seedCookies(
        cookies.map((c) => '${c.name}=${c.value}').join('; '),
      );
    } catch (_) {
      // 撈不到不影響主要流程
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('論壇安全驗證')),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          TextButton(
            onPressed: () => _check(manual: true),
            child: Text(tr('我已完成')),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              tr(
                '論壇開啟了 Cloudflare 安全驗證。這一頁通過之後 App 就能正常使用，'
                '通常只要等幾秒，有時要點一下「我是人類」。',
              ),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: subtle(context),
              ),
            ),
          ),
          Expanded(
            child: _controller == null
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
