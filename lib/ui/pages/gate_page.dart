import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/ui.dart';
import '../../services/page_reload_stub.dart'
    if (dart.library.js_interop) '../../services/page_reload_web.dart';
import '../../store/gate.dart';
import '../../theme.dart';
import '../widgets/launch_splash.dart';

/// 蓋在整個 App 上的「能不能用」判斷：測試碼、維護、強制更新、連不上。
///
/// 放在 MaterialApp.builder 裡（Navigator 之上），所以：
/// * 還沒確認能用之前**不建立**底下的頁面——網頁版在這之前打論壇只會
///   一路撞 403，原生版也沒必要先載一堆東西。
/// * 用過之後才被蓋住的（維護臨時開啟）只是藏起來，結束後回到原本的頁面。
class GateHost extends StatefulWidget {
  const GateHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.splash = true,
  });
  final Widget? child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// 開機時蓋一層啟動動畫，等知道要顯示哪一頁才淡出（測試可以關掉）
  final bool splash;

  @override
  State<GateHost> createState() => _GateHostState();
}

class _GateHostState extends State<GateHost> {
  bool _everOpen = false;
  bool _splashDone = false;
  int? _offered;

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateStore>();
    if (gate.isOpen) {
      _everOpen = true;
      _maybeOfferUpdate(gate);
    }
    return Stack(
      children: [
        if (_everOpen)
          Offstage(
            offstage: !gate.isOpen,
            child: TickerMode(enabled: gate.isOpen, child: widget.child ?? const SizedBox()),
          ),
        if (!gate.isOpen)
          Positioned.fill(
            // 這層在 Navigator 之上，沒有 Overlay——輸入框的選字工具列會找不到地方畫。
            // Overlay 的 initialEntries 只在第一次建立時用，裡面的畫面**要自己聽
            // 狀態變化**：不聽的話從「檢查中」變成「輸入測試碼」時畫面不會換，
            // 會一直卡在檢查中
            child: Overlay(initialEntries: [
              OverlayEntry(
                builder: (_) => ListenableBuilder(
                  listenable: gate,
                  builder: (_, _) => GateScreen(gate: gate),
                ),
              ),
            ]),
          ),
        if (widget.splash && !_splashDone)
          Positioned.fill(
            child: LaunchSplash(
              // 開機流程還在跑、或第一次開還在問伺服器
              ready: gate.stage != GateStage.checking,
              waitingLabel: tr('連線中…'),
              onDone: () => setState(() => _splashDone = true),
            ),
          ),
      ],
    );
  }

  /// 有新版就提醒一次。「略過這一版」之後同一版不再跳
  void _maybeOfferUpdate(GateStore gate) {
    final u = gate.update;
    if (u == null || _offered == u.build) return;
    _offered = u.build;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_kSkip) == u.build) return;
      final ctx = widget.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final skip = await showUpdateDialog(ctx, gate, u);
      if (skip) await prefs.setInt(_kSkip, u.build);
    });
  }
}

const _kSkip = 'gm.update.skip';

/// 有新版的對話框。回傳 true＝使用者選了「略過這一版」
Future<bool> showUpdateDialog(BuildContext context, GateStore gate, UpdateInfo u) async {
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(LucideIcons.download),
      title: Text(kIsWeb ? tr('網頁版有新版本') : tr('有新版本 ${u.version}')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('目前 ${gate.version}，最新 ${u.version.isEmpty ? 'build ${u.build}' : u.version}'),
                style: TextStyle(fontSize: 13, color: subtle(c))),
            if (u.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(u.notes, style: const TextStyle(fontSize: 14, height: 1.55)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, 'skip'), child: Text(tr('略過這一版'))),
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('稍後'))),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'go'),
          child: Text(kIsWeb ? tr('重新整理') : tr('更新')),
        ),
      ],
    ),
  );
  if (r == 'go' && context.mounted) await openUpdate(context, gate, u);
  return r == 'skip';
}

/// 前往更新。Android 直接下載 APK；iOS 可以下載 IPA（LiveContainer 等）或
/// 叫 SideStore 自己更新；網頁版重新整理就是新版
Future<void> openUpdate(BuildContext context, GateStore gate, UpdateInfo? u) async {
  if (kIsWeb) return reloadPage();
  if (u == null || u.url.isEmpty) return;
  if (gate.platform != 'ios') {
    await launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
    return;
  }
  final pick = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LucideIcons.store),
            title: Text(tr('用 SideStore 更新')),
            subtitle: Text(tr('從 SideStore 安裝的選這個')),
            onTap: () => Navigator.pop(c, 'sidestore'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.fileDown),
            title: Text(tr('下載 IPA')),
            subtitle: Text(tr('LiveContainer 或其他側載工具用')),
            onTap: () => Navigator.pop(c, 'ipa'),
          ),
        ],
      ),
    ),
  );
  if (pick == 'ipa') {
    await launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
  } else if (pick == 'sidestore' && context.mounted) {
    await openSideStoreSource(context, gate);
  }
}

/// 把更新來源加進 SideStore（已經加過的話只是打開它）。開不了就複製網址
Future<void> openSideStoreSource(BuildContext context, GateStore gate) async {
  final src = gate.sourceUrl.isNotEmpty ? gate.sourceUrl : '${GateStore.origin}/api/app/source.json';
  final ok = await launchUrl(
    Uri.parse('sidestore://source?url=${Uri.encodeComponent(src)}'),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (ok || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: src));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('已複製來源網址')),
      content: Text(tr('打不開 SideStore。請在 SideStore 的「來源（Sources）」按 + 貼上：\n\n$src')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('知道了')))],
    ),
  );
}

/// 各種擋下來的畫面
class GateScreen extends StatelessWidget {
  const GateScreen({super.key, required this.gate});
  final GateStore gate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (gate.stage) {
                GateStage.checking || GateStage.open => const _Checking(),
                GateStage.needCode => _CodeForm(gate: gate),
                GateStage.maintenance => _Info(
                    icon: LucideIcons.wrench,
                    title: tr('維護中'),
                    body: gate.maintenanceMessage.isNotEmpty
                        ? gate.maintenanceMessage
                        : tr('系統維護中，請稍後再試。'),
                    gate: gate,
                  ),
                GateStage.updateRequired => _Info(
                    icon: LucideIcons.download,
                    title: tr('需要更新'),
                    body: tr('這個版本（${gate.version}）已停止支援，請更新'
                        '${gate.update == null ? '' : '到 ${gate.update!.version}'}後再使用。'),
                    notes: gate.update?.notes ?? '',
                    gate: gate,
                    primary: (tr('更新'), () => openUpdate(context, gate, gate.update)),
                  ),
                GateStage.unreachable => _Info(
                    icon: LucideIcons.wifiOff,
                    title: tr('連不上伺服器'),
                    body: tr('需要確認測試資格，但目前連不上伺服器。請確認網路後重試。'),
                    gate: gate,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.4),
          const SizedBox(height: 16),
          Text(tr('檢查中…'), style: TextStyle(color: subtle(context))),
        ],
      );
}

class _Info extends StatefulWidget {
  const _Info({
    required this.icon,
    required this.title,
    required this.body,
    required this.gate,
    this.notes = '',
    this.primary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String notes;
  final GateStore gate;
  final (String, VoidCallback)? primary;

  @override
  State<_Info> createState() => _InfoState();
}

class _InfoState extends State<_Info> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.gate.check(force: true);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: 46, color: scheme.primary),
        const SizedBox(height: 16),
        Text(widget.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(widget.body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.6, color: subtle(context))),
        if (widget.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(widget.notes, style: const TextStyle(fontSize: 14, height: 1.55)),
          ),
        ],
        const SizedBox(height: 24),
        if (widget.primary case (final label, final onTap)) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onTap, child: Text(label)),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _retry,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('重試')),
          ),
        ),
      ],
    );
  }
}

class _CodeForm extends StatefulWidget {
  const _CodeForm({required this.gate});
  final GateStore gate;

  @override
  State<_CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends State<_CodeForm> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final err = await widget.gate.activate(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = err == null ? null : tr(err);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(LucideIcons.ticket, size: 46, color: scheme.primary),
        const SizedBox(height: 16),
        Text(tr('輸入測試碼'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          tr('GameMale 目前在測試階段，需要測試碼才能使用。'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.6, color: subtle(context)),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _ctrl,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 19, letterSpacing: 1.5, fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            hintText: 'GMXX-XXXX-XXXX',
            errorText: _err,
            errorMaxLines: 3,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('啟用')),
        ),
        const SizedBox(height: 18),
        Text(
          tr('啟用後，這台裝置的型號、系統版本、App 版本、IP，以及登入的論壇暱稱與 UID '
              '會提供給測試管理者，用來管理測試資格。不會收集密碼或登入資料。'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.55, color: faint(context)),
        ),
        const SizedBox(height: 8),
        Text(
          tr('裝置識別碼：${widget.gate.deviceId.length > 8 ? widget.gate.deviceId.substring(0, 8) : widget.gate.deviceId}'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: faint(context)),
        ),
      ],
    );
  }
}

/// 設定頁「檢查更新」用
Future<void> checkUpdateNow(BuildContext context) async {
  final gate = context.read<GateStore>();
  await gate.check(force: true);
  if (!context.mounted) return;
  final u = gate.update;
  if (u == null) {
    unawaited(showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('已是最新版本')),
        content: Text(tr('目前版本 ${gate.version}（${gate.build}）')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('好')))],
      ),
    ));
    return;
  }
  await showUpdateDialog(context, gate, u);
}
