import '../../i18n/ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gm_api/http.dart';
import '../../services/cache_manager.dart';
import '../../store/gate.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import '../widgets/toast.dart';
import 'gate_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 論壇本尊的網域。**不要用 kOrigin**——網頁版那個是自己的轉發位址。
final _forumHost = Uri.parse(kForumOrigin).host;

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final settings = context.watch<SettingsStore>();

    return Scaffold(
      appBar: AppBar(title: Text(tr('設定'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _section(context, tr('外觀')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _choice<AppLang>(
                  context,
                  icon: LucideIcons.languages,
                  title: tr('語言'),
                  current: settings.lang,
                  values: AppLang.values,
                  labelOf: (v) => v.label,
                  descOf: (v) => v.desc,
                  onPick: settings.setLang,
                  trailingNote: settings.lang == AppLang.auto
                      ? (settings.toTraditional ? tr('目前：繁體') : tr('目前：简体'))
                      : null,
                  note: settings.toTraditional
                      ? tr('只影響 App 介面。帖子內容一律保留論壇原文，'
                          '想看繁體請在帖子頁按右上角的翻譯')
                      : tr('只影響 App 介面。帖子內容一律保留論壇原文'),
                ),
                const Divider(indent: 56, endIndent: 14),
                _choice<ThemeMode>(
                  context,
                  icon: LucideIcons.moon,
                  title: tr('主題'),
                  current: settings.themeMode,
                  values: ThemeMode.values,
                  labelOf: (v) => switch (v) {
                    ThemeMode.system => tr('跟隨系統'),
                    ThemeMode.light => tr('淺色'),
                    ThemeMode.dark => tr('深色'),
                  },
                  descOf: (_) => null,
                  onPick: settings.setThemeMode,
                ),
                const Divider(indent: 56, endIndent: 14),
                _accentRow(context, settings),
              ],
            ),
          ),
          _section(context, tr('流量')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _choice<ImagePolicy>(
                  context,
                  icon: LucideIcons.image,
                  title: tr('帖子圖片載入'),
                  current: settings.imagePolicy,
                  values: ImagePolicy.values,
                  labelOf: (v) => v.label,
                  descOf: (v) => v.desc,
                  onPick: settings.setImagePolicy,
                  trailingNote: settings.imagePolicy == ImagePolicy.wifiOnly
                      ? (settings.onWifi ? tr('目前：Wi-Fi') : tr('目前：行動網路'))
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 26, 0),
            child: Text(
              tr('設為手動時，帖子裡的圖片會先顯示佔位，點一下才載入。'
                  '長按任何圖片可以儲存、分享或複製原始連結。'),
              style: TextStyle(fontSize: 12.5, height: 1.6, color: faint(context)),
            ),
          ),
          _section(context, tr('增強功能')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  // 沒登入就一律顯示關、也不給切——這三項都要有登入狀態
                  // 才有作用，開著只會讓人以為在運作
                  value: session.loggedIn && settings.markReplied,
                  secondary: const Icon(LucideIcons.replyAll),
                  title: Text(tr('標記已回過的帖')),
                  subtitle: Text(
                    session.loggedIn
                        ? tr('主題列表會在標題前標「已回」。每個主題都要單獨問論壇一次，'
                            '列表出來後會慢慢補上')
                        : tr('請先登入論壇'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged:
                      session.loggedIn ? settings.setMarkReplied : null,
                ),
                const Divider(indent: 56, endIndent: 14),
                SwitchListTile(
                  value: session.loggedIn && settings.autoSign,
                  secondary: const Icon(LucideIcons.calendarCheck),
                  title: Text(tr('每天自動簽到')),
                  subtitle: Text(
                    session.loggedIn
                        ? tr('每天第一次開 App 會自動幫你點簽到')
                        : tr('請先登入論壇'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged: session.loggedIn ? settings.setAutoSign : null,
                ),
              ],
            ),
          ),
          _section(context, tr('帳號')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _row(context, tr('使用者'), session.name.isEmpty ? '—' : session.name),
                const Divider(indent: 14, endIndent: 14),
                _row(context, 'UID', '${session.uid ?? '—'}'),
                const Divider(indent: 14, endIndent: 14),
                _row(context, tr('登入狀態'), session.loggedIn ? tr('已登入') : tr('未登入')),
              ],
            ),
          ),
          _section(context, tr('儲存空間')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: _CacheTile(),
          ),
          _section(context, tr('版本與更新')),
          const Card(clipBehavior: Clip.antiAlias, child: _VersionCard()),
          _section(context, tr('關於')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: Text(tr('用瀏覽器開啟論壇')),
                  trailing: Icon(LucideIcons.externalLink, size: 18, color: faint(context)),
                  // 開論壇本站：網頁版的轉發網址整頁打開會變訪客、圖片被防盜連擋
                  onTap: () => launchUrl(
                    Uri.parse('$kForumOrigin/forum.php'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 0),
            child: Text(
              // 帳密永遠是送到論壇本尊，不能寫成 kOrigin——網頁版的 kOrigin
              // 是自己的轉發位址，那樣會顯示成「帳密只送往 852111.xyz/gm」。
              //
              // 網頁版也不能沿用「不經過任何第三方伺服器」那句：瀏覽器不准
              // 跨網域直接連論壇，請求確實會經過自己架的轉發。講清楚比較好。
              kIsWeb
                  ? tr('瀏覽器不准跨網域直接連論壇，所以網頁版經由 ') +
                      Uri.base.host +
                      tr(' 轉發。轉發不保存任何帳號資料，'
                          '登入狀態由瀏覽器自己保管；帳密最終送往 ') +
                      _forumHost +
                      tr('。')
                  : tr('這個 App 直接讀論壇的手機版頁面，不經過任何第三方伺服器，'
                          '帳密只送往 ') +
                      _forumHost +
                      tr('。'),
              style: TextStyle(fontSize: 12.5, height: 1.7, color: faint(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) labelOf,
    required String? Function(T) descOf,
    required Future<void> Function(T) onPick,
    String? trailingNote,
    String? note,
  }) {
    final sub = [?trailingNote, ?note].join('\n');
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, style: const TextStyle(fontSize: 12, height: 1.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(labelOf(current),
              style: TextStyle(fontSize: 14, color: subtle(context))),
          Icon(LucideIcons.chevronRight, size: 18, color: faint(context)),
        ],
      ),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                // Flutter 3.32 起 RadioListTile 的 groupValue/onChanged 改由 RadioGroup 統一管理
                RadioGroup<T>(
                  groupValue: current,
                  onChanged: (x) => Navigator.pop(sheet, x),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final v in values)
                        RadioListTile<T>(
                          value: v,
                          title: Text(labelOf(v)),
                          subtitle: descOf(v) == null
                              ? null
                              : Text(descOf(v)!, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (picked != null) await onPick(picked);
      },
    );
  }

  /// 強調色用色票列，比下拉選單直觀
  Widget _accentRow(BuildContext c, SettingsStore settings) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Row(
          children: [
            const SizedBox(width: 40, child: Icon(LucideIcons.palette)),
            Expanded(child: Text(tr('強調色'))),
            for (final a in Accent.values)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => settings.setAccent(a),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: a.seed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.accent == a
                            ? Theme.of(c).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: settings.accent == a
                        ? const Icon(LucideIcons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _section(BuildContext c, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: Text(title,
            style:
                TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: faint(c))),
      );

  Widget _row(BuildContext c, String label, String value) => ListTile(
        title: Text(label),
        trailing: Text(value, style: TextStyle(fontSize: 14, color: subtle(c))),
      );
}


/// 圖片快取的大小與清除。網頁版量不到磁碟大小（瀏覽器自己管），
/// 那時只顯示清除鈕。
class _CacheTile extends StatefulWidget {
  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  int? _bytes;
  bool _known = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final b = await cacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _known = true;
    });
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await clearImageCache();
    await _measure();
    if (!mounted) return;
    setState(() => _clearing = false);
    toast(context, tr('已清除圖片快取'));
  }

  @override
  Widget build(BuildContext context) {
    final size = _bytes != null ? formatBytes(_bytes) : null;
    return ListTile(
      leading: const Icon(LucideIcons.hardDrive),
      title: Text(tr('清除圖片快取')),
      subtitle: Text(
        !_known
            ? tr('計算中…')
            : size != null
                ? (kIsWeb
                    ? tr('記憶體中的圖片 ') + size + tr('（磁碟快取由瀏覽器管理）')
                    : tr('目前佔用 ') + size)
                : tr('無法取得大小'),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: _clearing
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(onPressed: _clear, child: Text(tr('清除'))),
    );
  }
}

/// 版本、檢查更新、更新日誌、測試資格
class _VersionCard extends StatelessWidget {
  const _VersionCard();

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateStore>();
    final meta = TextStyle(fontSize: 12.5, color: faint(context));
    final exp = gate.codeExpiresAt;
    final u = gate.update;

    return Column(
      children: [
        ListTile(
          title: Text(tr('目前版本')),
          trailing: Text('${gate.version} (${gate.build})', style: TextStyle(color: subtle(context))),
        ),
        const Divider(indent: 14, endIndent: 14),
        ListTile(
          title: Text(tr('檢查更新')),
          subtitle: u == null ? null : Text(tr('有新版本 ${u.version}'), style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.primary)),
          trailing: Icon(LucideIcons.refreshCw, size: 18, color: faint(context)),
          onTap: () => checkUpdateNow(context),
        ),
        const Divider(indent: 14, endIndent: 14),
        ListTile(
          title: Text(tr('更新日誌')),
          trailing: Icon(LucideIcons.chevronRight, size: 18, color: faint(context)),
          onTap: () => context.push('/changelog'),
        ),
        if (gate.platform == 'ios') ...[
          const Divider(indent: 14, endIndent: 14),
          ListTile(
            title: Text(tr('加入 SideStore 更新來源')),
            subtitle: Text(tr('加入後 SideStore 會自己顯示新版、一鍵更新'), style: meta),
            trailing: Icon(LucideIcons.externalLink, size: 18, color: faint(context)),
            onTap: () => openSideStoreSource(context, gate),
          ),
        ],
        if (gate.maintenanceBypassed) ...[
          const Divider(indent: 14, endIndent: 14),
          ListTile(
            leading: Icon(LucideIcons.wrench, size: 18, color: Theme.of(context).colorScheme.error),
            title: Text(tr('維護模式中')),
            subtitle: Text(tr('你的測試碼可以略過維護，其他人目前看到的是維護畫面'), style: meta),
          ),
        ],
        if (gate.hasCode) ...[
          const Divider(indent: 14, endIndent: 14),
          ListTile(
            title: Text(tr('測試碼')),
            subtitle: Text(
              exp == null
                  ? gate.codeHint
                  : '${gate.codeHint}・${tr('到期')} ${exp.year}/${exp.month}/${exp.day}',
              style: meta,
            ),
            trailing: TextButton(
              onPressed: () => _unbind(context, gate),
              child: Text(tr('解除此裝置')),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _unbind(BuildContext context, GateStore gate) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('解除此裝置？')),
        content: Text(tr(gate.betaRequired
            ? '這台裝置會釋出測試碼的名額，之後要重新輸入測試碼才能使用。'
            : '這台裝置會釋出測試碼的名額。目前已正式開放，解除後仍可正常使用。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('解除'))),
        ],
      ),
    );
    if (ok == true) await gate.unbind();
  }
}
