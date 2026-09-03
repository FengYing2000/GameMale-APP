import 'dart:io' show Platform;

import '../../i18n/ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gm_api/http.dart';
import '../../services/background.dart';
import '../../services/cache_manager.dart';
import '../../services/web_push_stub.dart'
    if (dart.library.js_interop) '../../services/web_push.dart';
import '../../services/notifications.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import '../widgets/toast.dart';

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

  /// 打開通知要先跟系統要權限；使用者拒絕就不要把開關留在開著
  Future<void> _setNotify(SettingsStore settings, bool on) async {
    if (!on) {
      await settings.setNotifyBackground(false);
      if (kIsWeb) {
        await WebPush.disable();
      } else {
        await disableBackgroundBadges();
      }
      return;
    }

    // 網頁版走瀏覽器的 Web Push，跟原生的本地通知是兩套完全不同的東西
    if (kIsWeb) {
      if (WebPush.support == WebPushSupport.needInstall) {
        if (mounted) {
          toast(context, tr('iOS 要先把網頁「加入主畫面」，再從那個圖示打開才收得到推播'),
              kind: ToastKind.warn);
        }
        return;
      }
      if (WebPush.support == WebPushSupport.unsupported) {
        if (mounted) {
          toast(context, tr('這個瀏覽器不支援推播'), kind: ToastKind.warn);
        }
        return;
      }
      final err = await WebPush.enable();
      if (!mounted) return;
      if (err != null) {
        toast(context, tr(err), kind: ToastKind.warn);
        return;
      }
      await settings.setNotifyBackground(true);
      return;
    }

    final granted = await Notifications.requestPermission();
    if (!mounted) return;
    if (!granted) {
      toast(context, tr('沒有通知權限，請到系統設定裡允許'), kind: ToastKind.warn);
      return;
    }
    await settings.setNotifyBackground(true);
    await enableBackgroundBadges();
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
                const Divider(indent: 56, endIndent: 14),
                SwitchListTile(
                  value: session.loggedIn && settings.notifyBackground,
                  secondary: const Icon(LucideIcons.bellRing),
                  title: Text(tr('新提醒通知')),
                  // 沒登入就不給開：綁定通知要拿論壇的登入狀態去認人，
                  // 這時候按下去只會拿到一句「請先登入」，而且權限一旦
                  // 被拒就再也問不了。
                  onChanged: session.loggedIn
                      ? (v) => _setNotify(settings, v)
                      : null,
                  subtitle: Text(
                    // Platform.isIOS 在網頁版會直接丟例外，一定要先擋掉
                    kIsWeb
                        ? (session.loggedIn
                            ? tr('由伺服器定期查有沒有新提醒／私訊，有就推播過來。'
                                '網頁版關掉也收得到，但 iOS 要先把網頁加入主畫面。')
                            : tr('請先登入論壇'))
                        : Platform.isIOS
                            ? tr('背景時定期查有沒有新提醒／私訊，有就發通知。'
                                'iOS 由系統決定何時喚醒，通常隔十幾分鐘到幾小時；'
                                '把 App 從切換器上滑掉強制關閉就完全不會查。')
                            : tr('背景時定期查有沒有新提醒／私訊，有就發通知。'
                                '最短 15 分鐘一次；被系統「強制停止」或省電機制清掉才會停。'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 26, 0),
            child: Text(
              tr('這一區放的是論壇網頁版沒有、App 自己加的功能。'),
              style: TextStyle(fontSize: 12.5, height: 1.6, color: faint(context)),
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
          _section(context, tr('儲存空間')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: _CacheTile(),
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
                  trailing: Icon(LucideIcons.externalLink, size: 18, color: faint(context)),
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
