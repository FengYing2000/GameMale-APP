import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../i18n/ui.dart';
import '../../services/web_push_stub.dart'
    if (dart.library.js_interop) '../../services/web_push.dart';

const _kAskedKey = 'web_push_asked';

/// 網頁版第一次開起來時該講的兩件事。
///
/// * 還在 Safari 分頁裡 → 教他加到主畫面（不加就永遠收不到推播）
/// * 已經是主畫面 App 但沒開通知 → 問一次要不要開
///
/// **不能自動跳權限視窗**：瀏覽器規定 `Notification.requestPermission()`
/// 一定要在使用者的點擊裡呼叫，自動跑會被擋掉，而且擋掉之後就再也問不了。
/// 所以這裡先問一次「要不要開」，按了才去要權限。
Future<void> maybeShowWebOnboarding(
  BuildContext context, {
  required bool loggedIn,
}) async {
  if (!kIsWeb) return;

  final support = WebPush.support;
  if (support == WebPushSupport.unsupported) return;

  // 還在瀏覽器分頁裡的話，加到主畫面的引導交給首頁那張常駐橫幅
  // （見 widgets/install_banner.dart）——啟動時跳一次的視窗太容易錯過。
  if (support == WebPushSupport.needInstall) return;

  // 已經開好了就不用再囉嗦
  if (WebPush.permission == 'granted') return;
  // **還沒登入就先別問**：綁定通知需要論壇的登入狀態，這時候問了、
  // 使用者按了同意，也只會拿到一句「請先登入」。
  // 加到主畫面之後是全新的儲存空間，本來就會是未登入狀態，很常見。
  if (!loggedIn) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kAskedKey) ?? false) return;
  if (!context.mounted) return;
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => const _OnboardingSheet(),
  );
  // 只有真的處理完（開好了、或明確說以後再說）才記起來。
  // 中途出錯就不要記，否則使用者下次再也不會被問到。
  if (done == true) await prefs.setBool(_kAskedKey, true);
}

class _OnboardingSheet extends StatefulWidget {
  const _OnboardingSheet();

  @override
  State<_OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<_OnboardingSheet> {
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
          children: [
            Icon(LucideIcons.bellRing, size: 30, color: scheme.primary),
            const SizedBox(height: 14),
            Text(
              tr('要開啟通知嗎？'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              tr('有新提醒或新私訊時通知你。就算沒開著也收得到。'),
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
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
          ],
        ),
      ),
    );
  }
}
