/// 原生版用不到 Web Push（走本地通知 + workmanager），
/// 但 `settings_page` 是共用的，所以留一份同介面的空殼，
/// 讓條件式 import 在原生端也編得過。
enum WebPushSupport { ok, needInstall, unsupported }

class WebPush {
  WebPush._();
  static WebPushSupport get support => WebPushSupport.unsupported;
  static String get permission => 'unsupported';
  static Future<String?> enable() async => '這個平台不用 Web Push';
  static Future<bool> isSubscribed() async => false;
  static Future<bool> ensureSubscribed() async => false;
  static Future<void> disable() async {}
}
