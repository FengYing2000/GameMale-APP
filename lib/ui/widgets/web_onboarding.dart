import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/ui.dart';
import '../../services/web_push_stub.dart'
    if (dart.library.js_interop) '../../services/web_push.dart';

const _kAskedKey = 'web_push_asked';

/// 這次開啟已經跳過哪些引導了（只存在記憶體裡）。
///
/// 兩種分開記：使用者可能先在分頁裡看過安裝教學，加到主畫面、登入之後
/// 還要再問一次通知。共用一個旗標的話第二個就永遠跳不出來。
bool _installShown = false;
bool _notifyAsked = false;

/// 網頁版的引導。**從首頁的 post-frame 呼叫**——那裡一定有可用的 Scaffold
/// context，比從根導覽器抓可靠得多（之前那樣常常抓不到，整個沒跳）。
///
/// 兩種情況：
/// * 還在 Safari 分頁裡 → 教他加到主畫面（不裝就永遠收不到推播）。
///   每次瀏覽提醒一次；首頁也有一張常駐橫幅可以隨時再看。
/// * 已經是主畫面 App 但沒開通知 → 問要不要開（要登入後才問，因為綁定
///   通知需要論壇登入狀態）。
Future<void> maybeShowWebOnboarding(
  BuildContext context, {
  required bool loggedIn,
}) async {
  if (!kIsWeb) return;

  final support = WebPush.support;
  if (support == WebPushSupport.unsupported) return;

  final installing = support == WebPushSupport.needInstall;

  if (installing) {
    // 加到主畫面：每次瀏覽跳一次就好
    if (_installShown) return;
    _installShown = true;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _Sheet(installing: true),
    );
    return;
  }

  // 已經是主畫面 App。
  if (WebPush.permission == 'granted') return;
  // 還沒登入就先別問——綁定通知需要論壇登入狀態，這時候問了、使用者按了
  // 同意，也只會拿到一句「請先登入」。加到主畫面後本來就是未登入狀態。
  if (!loggedIn) return;

  if (_notifyAsked) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kAskedKey) ?? false) return;
  _notifyAsked = true;
  if (!context.mounted) return;
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _Sheet(installing: false),
  );
  // 中途出錯就不要記成問過，否則使用者下次再也不會被問到
  if (done == true) await prefs.setBool(_kAskedKey, true);
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.installing});
  final bool installing;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _busy = false;
  String? _error;

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await WebPush.enable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children:
              widget.installing ? _installBody(scheme) : _notifyBody(scheme),
        ),
      ),
    );
  }

  List<Widget> _installBody(ColorScheme scheme) => [
        Icon(LucideIcons.share, size: 30, color: scheme.primary),
        const SizedBox(height: 14),
        Text(tr('把 GameMale 加到主畫面'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          tr('加到主畫面後，開起來就跟一般 App 一樣（沒有網址列、全螢幕），'
              '而且才收得到新提醒與私訊的推播 —— iOS 只讓主畫面的 App 收推播。'),
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        _step(scheme, 1, tr('點瀏覽器下方正中間的「分享」鈕'), LucideIcons.share),
        _step(scheme, 2, tr('往下捲，選「加入主畫面」'), LucideIcons.squarePlus),
        _step(scheme, 3, tr('回到主畫面，從 GameMale 圖示打開'), LucideIcons.house),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('知道了')),
          ),
        ),
      ];

  List<Widget> _notifyBody(ColorScheme scheme) => [
        Icon(LucideIcons.bellRing, size: 30, color: scheme.primary),
        const SizedBox(height: 14),
        Text(tr('要開啟通知嗎？'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(tr('有新提醒或新私訊時通知你，就算沒開著也收得到。'),
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        if (_error != null) ...[
          Text(tr(_error!),
              style: TextStyle(fontSize: 13, color: scheme.error)),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _enable,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('開啟通知')),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, true),
            child: Text(tr('以後再說')),
          ),
        ),
      ];

  Widget _step(ColorScheme scheme, int n, String text, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .15),
                  shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$n',
                  style: TextStyle(fontSize: 12, color: scheme.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5))),
            Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          ],
        ),
      );
}
