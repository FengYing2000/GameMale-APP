import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gm_api/http.dart';

import '../../i18n/ui.dart';
import '../../services/browser_fetch_stub.dart'
    if (dart.library.io) '../../services/browser_fetch.dart';
import '../../theme.dart';

/// 論壇的 Cloudflare 安全驗證。
///
/// **這裡顯示的就是平常在背後發請求的那顆 WebView**，不是另外開一個。
///
/// 開兩顆會壞掉：使用者在看得見的那顆解完，背後那顆還停在挑戰頁上——
/// 而它是透明的，連「我是人類」都點不到，於是永遠解不開。實機上的症狀是
/// 按了「我已完成」卻跳出「需要先通過論壇的安全驗證」。
///
/// 一個 controller 同時只能掛在一個 WebViewWidget 上，所以進來時要請
/// 常駐的宿主讓位（`presenting`），離開時再還回去。
class CfChallengePage extends StatefulWidget {
  const CfChallengePage({super.key});

  @override
  State<CfChallengePage> createState() => _CfChallengePageState();
}

class _CfChallengePageState extends State<CfChallengePage> {
  WebViewController? _controller;
  bool _done = false;
  bool _checking = false;

  /// 按過「我已完成」但其實還沒過——用來提示，而不是硬關掉這一頁
  bool _notYet = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 還沒建立過就先讓它建起來（例如直連時就撞到挑戰）
    BrowserFetch.instance.warmUp();
    BrowserFetch.instance.presenting.value = true;

    // 控制器可能還在建，等它出現
    for (var i = 0; i < 20 && mounted; i++) {
      final c = BrowserFetch.instance.controller;
      if (c != null) {
        setState(() => _controller = c);
        _watch(c);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 挑戰過關之後 Cloudflare 會自己導回論壇，這裡等那一刻
  void _watch(WebViewController c) {
    c.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => _check()),
    );
    _check();
  }

  /// 判斷「解開了沒」要看**畫面上真的是論壇了**，不能看 cookie 存不存在。
  ///
  /// 踩過這個坑：上一次解出來的 `cf_clearance` 還留在 cookie store 裡，
  /// 於是這頁一打開就以為已經成功、立刻自己關掉——使用者看到的是驗證頁
  /// 一閃而過，然後什麼都沒解決。票還在不代表它還有效。
  static const _probeJs = """
(function () {
  var h = document.documentElement ? document.documentElement.innerHTML : '';
  if (h.indexOf('challenge-platform') >= 0 || h.indexOf('_cf_chl_opt') >= 0) {
    return 'challenge';
  }
  return document.querySelector('#hd, #nv, .bm, #ft, #postlist') ? 'forum' : 'other';
})()
""";

  Future<bool> _isForum(WebViewController c) async {
    try {
      final r = await c.runJavaScriptReturningResult(_probeJs);
      // 平台之間回傳格式不一致（有的帶引號），統一拆掉再比
      return r.toString().replaceAll('"', '') == 'forum';
    } catch (_) {
      return false;
    }
  }

  Future<void> _check({bool manual = false}) async {
    if (_done || _checking) return;
    final c = _controller;
    if (c == null) return;
    _checking = true;
    try {
      if (!await _isForum(c)) {
        // 手動按了才提示；自動探測失敗就安靜地繼續等
        if (manual && mounted) setState(() => _notYet = true);
        return;
      }
      await _harvest();
      _done = true;
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      _checking = false;
    }
  }

  /// 順手把 cookie 撈回 App。
  ///
  /// 主要的通行靠這顆 WebView 自己發請求，但論壇解除驗證後會切回直連，
  /// 那時這份 cookie 就派得上用場。`cf_clearance` 是 HttpOnly，
  /// `document.cookie` 讀不到，只能走平台的 cookie store。
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
  void dispose() {
    // 把 WebView 還給常駐的宿主，並恢復它平常的導覽處理
    BrowserFetch.instance.presenting.value = false;
    BrowserFetch.instance.restoreDelegate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            color: _notYet
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            child: Text(
              _notYet
                  ? tr('看起來還沒通過，請完成上面的驗證。通過之後這一頁會自己關閉。')
                  : tr(
                      '論壇開啟了 Cloudflare 安全驗證。通過之後這一頁會自己關閉，'
                      '通常只要等幾秒，有時要點一下「我是人類」。',
                    ),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: _notYet ? scheme.onErrorContainer : subtle(context),
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
