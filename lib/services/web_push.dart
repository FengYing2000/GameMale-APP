import 'dart:js_interop';

import 'package:dio/dio.dart';

/// 網頁版的推播。
///
/// Flutter 網頁版用不了 `flutter_local_notifications`（那是原生外掛），
/// 推播得走瀏覽器自己的 Push API。真正的實作在 `web/index.html` 的
/// `window.gmPush`，這裡只是把它接到 Dart。
///
/// 原生版走的是完全不同的一套（本地通知 + workmanager），見
/// `services/notifications.dart` 與 `services/background.dart`。
@JS('gmPush.supported')
external JSString _supported();

@JS('gmPush.status')
external JSString _status();

@JS('gmPush.enable')
external JSPromise<JSString> _enable();

@JS('gmPush.disable')
external JSPromise<JSString> _disable();

enum WebPushSupport {
  /// 可以用
  ok,

  /// iOS 要先加到主畫面才收得到推播
  needInstall,

  /// 這個瀏覽器沒有 Push API
  unsupported,
}

class WebPush {
  WebPush._();

  static WebPushSupport get support => switch (_supported().toDart) {
        'ok' => WebPushSupport.ok,
        'need-install' => WebPushSupport.needInstall,
        _ => WebPushSupport.unsupported,
      };

  /// 'granted' / 'denied' / 'default' / 'unsupported'
  static String get permission => _status().toDart;

  /// 要權限、訂閱、然後把訂閱回報給伺服器。
  ///
  /// **只能從使用者的點擊裡呼叫**——瀏覽器不接受自動跳出的權限請求。
  /// 成功回 null，失敗回錯誤訊息。
  static Future<String?> enable() async {
    final raw = (await _enable().toDart).toDart;
    if (raw.startsWith('error:')) return raw.substring(6);
    try {
      // 打的是**我們自己的**伺服器，不是論壇——Api 那條已經被指到
      // 論壇的轉發路徑上了，不能共用。
      await _own.post<void>('/api/web-subscribe', data: raw);
      return null;
    } on DioException catch (e) {
      final body = e.response?.data;
      return body is Map && body['error'] != null
          ? '${body['error']}'
          : (e.message ?? '訂閱沒送出去');
    }
  }

  static Future<void> disable() async {
    final endpoint = (await _disable().toDart).toDart;
    if (endpoint.isEmpty) return;
    try {
      await _own.post<void>('/api/unsubscribe', data: {'endpoint': endpoint});
    } catch (_) {
      // 伺服器那邊刪不掉也沒關係：推不動的訂閱它自己會清掉
    }
  }
}

/// 連自己伺服器用的 client（跟論壇那條是兩回事）。
/// 同源，所以瀏覽器會自動帶上登入 cookie。
final _own = Dio(BaseOptions(
  baseUrl: Uri.base.origin,
  contentType: Headers.jsonContentType,
  validateStatus: (s) => s != null && s < 400,
));
