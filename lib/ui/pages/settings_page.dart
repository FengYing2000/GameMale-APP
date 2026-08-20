import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '—';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

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
                  icon: Icons.translate,
                  title: tr('語言'),
                  current: settings.lang,
                  values: AppLang.values,
                  labelOf: (v) => v.label,
                  descOf: (v) => v.desc,
                  onPick: settings.setLang,
                  trailingNote: settings.lang == AppLang.auto
                      ? (settings.toTraditional ? tr('目前：繁體') : tr('目前：简体'))
                      : null,
                ),
                const Divider(indent: 56, endIndent: 14),
                _choice<ThemeMode>(
                  context,
                  icon: Icons.dark_mode_outlined,
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
                  icon: Icons.image_outlined,
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
          _section(context, tr('關於')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _row(context, tr('版本'), _version),
                const Divider(indent: 14, endIndent: 14),
                ListTile(
                  title: Text(tr('用瀏覽器開啟論壇')),
                  trailing: Icon(Icons.open_in_new, size: 18, color: faint(context)),
                  onTap: () => launchUrl(
                    Uri.parse('$kOrigin/forum.php'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 0),
            child: Text(
              tr('這個 App 直接讀論壇的手機版頁面，不經過任何第三方伺服器，'
                  '帳密只送往 ') +
                  kOrigin.replaceFirst('https://', '') +
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
  }) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: trailingNote == null
          ? null
          : Text(trailingNote, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(labelOf(current),
              style: TextStyle(fontSize: 14, color: subtle(context))),
          Icon(Icons.chevron_right, size: 18, color: faint(context)),
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
