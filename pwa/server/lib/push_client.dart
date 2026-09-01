import 'dart:convert';

import 'package:http/http.dart' as http;

import 'vapid.dart';
import 'webpush.dart';

/// 推播送出的結果。
enum PushOutcome {
  /// push service 收下了
  sent,

  /// 訂閱已失效（使用者移除了 App 或關掉通知）——要把它從資料庫刪掉，
  /// 繼續留著只會每次都失敗
  gone,

  /// 被限流，等一下再試
  rateLimited,

  /// 其他錯誤
  failed,
}

class PushResult {
  const PushResult(this.outcome, this.statusCode, [this.detail = '']);

  final PushOutcome outcome;
  final int statusCode;
  final String detail;

  bool get ok => outcome == PushOutcome.sent;

  @override
  String toString() => '${outcome.name}($statusCode)'
      '${detail.isEmpty ? '' : ' $detail'}';
}

/// 把訊息加密後送到 push service。
///
/// iOS 的限制要記得：**每一則推播都必須顯示通知**。不能拿它來偷偷同步
/// 紅點——Safari 發現你收了推播卻不顯示，會直接把通知權限收回去。
class PushClient {
  PushClient({
    required this.keys,
    required this.subject,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final VapidKeys keys;

  /// `mailto:` 或 https 網址，push service 出事時的聯絡方式
  final String subject;

  final http.Client _http;

  Future<PushResult> send({
    required PushSubscription subscription,
    required Map<String, dynamic> payload,
    Duration ttl = const Duration(hours: 12),
    String urgency = 'normal',
  }) async {
    final body = encryptPayload(
      plaintext: utf8.encode(json.encode(payload)),
      subscription: subscription,
    ).body;

    final jwt = keys.signJwt(endpoint: subscription.endpoint, subject: subject);

    try {
      final res = await _http.post(
        Uri.parse(subscription.endpoint),
        headers: {
          'Authorization': 'vapid t=$jwt, k=${keys.publicKeyBase64}',
          'Content-Encoding': 'aes128gcm',
          'Content-Type': 'application/octet-stream',
          'TTL': '${ttl.inSeconds}',
          'Urgency': urgency,
        },
        body: body,
      );

      return switch (res.statusCode) {
        200 || 201 || 202 => PushResult(PushOutcome.sent, res.statusCode),
        // 404/410 = 這個訂閱不存在了，呼叫端要負責刪掉
        404 || 410 => PushResult(PushOutcome.gone, res.statusCode),
        429 => PushResult(PushOutcome.rateLimited, res.statusCode),
        _ => PushResult(PushOutcome.failed, res.statusCode,
            res.body.length > 200 ? res.body.substring(0, 200) : res.body),
      };
    } catch (e) {
      return PushResult(PushOutcome.failed, 0, '$e');
    }
  }

  void close() => _http.close();
}
