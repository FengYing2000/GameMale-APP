import 'dart:async';

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
        // **先重載再判斷。**
        //
        // 這一頁被叫出來，就代表剛剛有請求失敗了。但 WebView 上可能還留著
        // 背景前渲染好的舊論壇頁面——不重載的話探測會說「是論壇」，這一頁
        // 立刻自己關掉，使用者只看到閃一下，而請求依然失敗。
        // 更糟的是那次假成功會啟動冷卻，害他按重試也叫不出這一頁。
        try {
          await c.reload();
        } catch (_) {
          // 重載失敗就照舊判斷，至少不會卡在這裡
        }
        _watch(c);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 挑戰過關之後 Cloudflare 會自己導回論壇，這裡等那一刻
  Timer? _poll;

  /// 挑戰過關之後 Cloudflare 會自己導回論壇，這裡等那一刻。
  ///
  /// **導覽事件不能當唯一依據**：傳輸層自己也會設導覽處理，兩邊搶同一顆
  /// WebView 時後設的會蓋掉先設的，事件就收不到了——實機症狀是驗證通過後
  /// 這一頁不會自己關，非得手動按「我已完成」。
  /// 所以同時用輪詢兜底，成本只是每一秒半跑一次很短的 JS。
  void _watch(WebViewController c) {
    c.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => _check()),
    );
    _check();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
  }

  /// 判斷「解開了沒」要看**畫面上真的是論壇了**，不能看 cookie 存不存在。
  ///
  /// 踩過這個坑：上一次解出來的 `cf_clearance` 還留在 cookie store 裡，
  /// 於是這頁一打開就以為已經成功、立刻自己關掉。票還在不代表它還有效。
  ///
  /// 探測邏輯跟傳輸層共用（`BrowserFetch.probeJs`）——分開寫會長歪，
  /// 而且那支踩過的兩個坑（桌面選擇器、CF 注入腳本）很難重新想起來。
  Future<bool> _isForum(WebViewController c) async {
    try {
      final r = await c.runJavaScriptReturningResult(BrowserFetch.probeJs);
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
      // **只拿 Cloudflare 的通行證，不要碰論壇的登入 cookie。**
      //
      // 一股腦全灌回去的話，只要 WebView 當下是未登入狀態（例如它自己
      // 載入時還沒拿到 App 的 cookie），就會用訪客的憑證蓋掉 App 原本
      // 登入好的那份——使用者莫名其妙變成「尚未登入」。
      final cf = cookies
          .where((c) => c.name.startsWith('cf_') || c.name.startsWith('__cf'))
          .toList();
      if (cf.isEmpty) return;
      await Api.instance.seedCookies(
        cf.map((c) => '${c.name}=${c.value}').join('; '),
      );
    } catch (_) {
      // 撈不到不影響主要流程
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
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
