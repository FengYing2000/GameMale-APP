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

@JS('gmPush.currentSubscription')
external JSPromise<JSString> _current();

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

  /// 伺服器那邊有沒有把推播整套關掉（`PUSH_ENABLED=false`）。
  ///
  /// 關掉時它不輪詢論壇、也不收訂閱，所以介面上不該再留通知的開關——
  /// 留著讓人按，按了也不會收到任何東西。
  static bool serverEnabled = true;

  /// 跟伺服器問一次設定。開機時做，失敗就沿用預設（當成開著）：
  /// 寧可多顯示一個開關，也不要因為一次網路抖動就把功能藏起來。
  static Future<void> loadServerConfig() async {
    try {
      final res = await _own.get<Map<String, dynamic>>('/api/config');
      serverEnabled = res.data?['pushEnabled'] as bool? ?? true;
    } catch (_) {
      // 問不到就當它是開的
    }
  }

  /// 這個瀏覽器還沒把網頁加到主畫面。
  ///
  /// **刻意不看 [serverEnabled]**：加到主畫面本身就有價值（沒有網址列、
  /// 全螢幕、有自己的圖示），推播關掉了那個引導還是該留著。
  static bool get needsInstall => _supported().toDart == 'need-install';

  static WebPushSupport get support {
    if (!serverEnabled) return WebPushSupport.unsupported;
    return switch (_supported().toDart) {
      'ok' => WebPushSupport.ok,
      'need-install' => WebPushSupport.needInstall,
      _ => WebPushSupport.unsupported,
    };
  }

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
      await _own.post<void>('/gm/__subscribe', data: raw);
      return null;
    } on DioException catch (e) {
      final body = e.response?.data;
      return body is Map && body['error'] != null
          ? '${body['error']}'
          : (e.message ?? '訂閱沒送出去');
    }
  }

  /// 這台裝置現在到底有沒有真的訂閱著。
  ///
  /// **不能只看本機的偏好設定**：把網頁重新加到主畫面會拿到全新的儲存空間
  /// 與新的 service worker，舊的訂閱留在伺服器上、這台卻什麼都沒有。
  /// 設定裡的開關看起來是開的，實際上一則都收不到。
  static Future<bool> isSubscribed() async =>
      (await _current().toDart).toDart.isNotEmpty;

  /// 權限已經給過的話，靜靜地把訂閱補回去並回報伺服器。
  ///
  /// 每次啟動都跑一次，這樣不管使用者重裝、換裝置、還是瀏覽器自己
  /// 換掉了訂閱，伺服器手上都會是最新的那一個。
  /// 權限沒給過就什麼都不做——要權限一定得在使用者的點擊裡。
  static Future<bool> ensureSubscribed() async {
    if (permission != 'granted') return false;
    if (support != WebPushSupport.ok) return false;
    return await enable() == null;
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
