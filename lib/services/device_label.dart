import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'install_hint_stub.dart' if (dart.library.js_interop) 'install_hint.dart';

/// 給控制台後台看的裝置描述：型號與系統版本。
///
/// 只有人看得懂的型號名稱與系統版本，沒有序號、廣告 ID 這類能追蹤人的東西。
/// 綁定測試碼的那一刻起才會送出（輸入測試碼的畫面上有寫）。
class DeviceLabel {
  const DeviceLabel({this.model = '', this.os = ''});

  /// iPhone 16 Pro／Samsung SM-S9180／Safari（主畫面）
  final String model;

  /// iOS 18.5／Android 15
  final String os;

  static Future<DeviceLabel> read() async {
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        return fromUserAgent(w.userAgent ?? '', standalone: isStandalone);
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          final i = await info.iosInfo;
          return DeviceLabel(
            model: i.isPhysicalDevice ? i.modelName : '模擬器（${i.modelName}）',
            os: 'iOS ${i.systemVersion}',
          );
        case TargetPlatform.android:
          final a = await info.androidInfo;
          final brand = a.manufacturer.isEmpty
              ? ''
              : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
          return DeviceLabel(
            model: a.isPhysicalDevice ? '$brand${a.model}'.trim() : '模擬器（${a.model}）',
            os: 'Android ${a.version.release}',
          );
        default:
          return DeviceLabel(model: defaultTargetPlatform.name);
      }
    } catch (_) {
      return const DeviceLabel();
    }
  }

  /// 網頁版從 User-Agent 認瀏覽器與系統
  @visibleForTesting
  static DeviceLabel fromUserAgent(String ua, {bool standalone = false}) {
    final browser = ua.contains('EdgiOS') || ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('SamsungBrowser')
            ? 'Samsung 瀏覽器'
            : ua.contains('Firefox') || ua.contains('FxiOS')
                ? 'Firefox'
                : ua.contains('CriOS') || ua.contains('Chrome')
                    ? 'Chrome'
                    : ua.contains('Safari')
                        ? 'Safari'
                        : '瀏覽器';

    var os = '';
    final ios = RegExp(r'(?:iPhone|CPU) OS (\d+)_(\d+)').firstMatch(ua);
    final android = RegExp(r'Android (\d+(?:\.\d+)?)').firstMatch(ua);
    if (ios != null) {
      os = '${ua.contains('iPad') ? 'iPadOS' : 'iOS'} ${ios[1]}.${ios[2]}';
    } else if (android != null) {
      os = 'Android ${android[1]}';
    } else if (ua.contains('Mac OS X')) {
      os = 'macOS';
    } else if (ua.contains('Windows')) {
      os = 'Windows';
    } else if (ua.contains('Linux')) {
      os = 'Linux';
    }
    return DeviceLabel(model: standalone ? '$browser（主畫面）' : browser, os: os);
  }
}
