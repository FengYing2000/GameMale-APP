import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../i18n/ui.dart';
import '../../services/web_push_stub.dart'
    if (dart.library.js_interop) '../../services/web_push.dart';

/// 「加到主畫面」的引導。
///
/// 做成常駐在首頁的橫幅，而不是啟動時跳一次的視窗——那種要抓對時機
/// （第一幀之後、context 已經有了、又還沒被使用者操作走），錯過就再也
/// 看不到，實測上很容易整個沒出現。橫幅只要條件成立就一直在，
/// 使用者什麼時候看到都算數。
///
/// 只在**瀏覽器分頁**裡出現：已經加到主畫面就沒必要再講。
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  bool _open = false;
  bool _hidden = false;

  bool get _needed =>
      kIsWeb && !_hidden && WebPush.support == WebPushSupport.needInstall;

  @override
  Widget build(BuildContext context) {
    if (!_needed) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.share, size: 20,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('加到主畫面'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 18, color: scheme.onPrimaryContainer),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr('開起來就跟一般 App 一樣，而且才收得到新提醒與私訊的推播'),
                style: TextStyle(
                    fontSize: 13, color: scheme.onPrimaryContainer),
              ),
              if (_open) ...[
                const SizedBox(height: 12),
                _step(scheme, 1, tr('點瀏覽器下方正中間的「分享」鈕')),
                _step(scheme, 2, tr('往下捲，選「加入主畫面」')),
                _step(scheme, 3, tr('回到主畫面，從那個圖示打開')),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _hidden = true),
                    child: Text(tr('不用了')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(ColorScheme scheme, int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: .15),
                  shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13.5, color: scheme.onPrimaryContainer)),
            ),
          ],
        ),
      );
}
