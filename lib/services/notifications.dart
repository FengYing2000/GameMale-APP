import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知。只有這支會發通知，前景背景共用。
///
/// 注意：這是**本地**通知，不是 APNs 推播。真正的推播要付費開發者帳號的
/// entitlement，免費憑證側載拿不到，所以只能靠背景輪詢後自己發。
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'gm_badges';

  /// 提醒與私訊各用固定 id，這樣新的會蓋掉舊的、不會疊一整排
  static const idNotice = 1;
  static const idPm = 2;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // 權限等使用者真的打開開關時再要，不要一啟動就跳
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    _ready = true;
  }

  /// 要通知權限（Android 13+ 與 iOS 都要問過才發得出來）
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '論壇提醒',
          channelDescription: '有新提醒或新私訊時通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
