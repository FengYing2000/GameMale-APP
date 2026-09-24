import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 伺服器自己簽、自己驗的 token：`base64url(payload).base64url(HMAC-SHA256)`。
///
/// 只有這台伺服器會驗，所以對稱式的 HMAC 就夠了（App 端只負責保管、
/// 原樣送回來）。payload 只放編號，不放任何能直接用的資料——測試碼被停用、
/// 裝置被解綁時，拿著舊 token 也會在比對資料時被擋下。
class TokenSigner {
  TokenSigner(List<int> key) : _hmac = Hmac(sha256, key);

  final Hmac _hmac;

  String sign(Map<String, Object?> payload) {
    final body = _b64(utf8.encode(json.encode(payload)));
    return '$body.${_b64(_hmac.convert(utf8.encode(body)).bytes)}';
  }

  /// 簽章不對、格式不對都回 null
  Map<String, Object?>? verify(String? token) {
    if (token == null) return null;
    final dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) return null;
    final body = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    final want = _b64(_hmac.convert(utf8.encode(body)).bytes);
    if (!constantTimeEquals(sig, want)) return null;
    try {
      final j = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(body))));
      return j is Map ? j.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

/// 比對密碼／簽章用：花的時間跟從哪個字開始不同無關，猜不出前綴對了幾個字
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

final _rand = Random.secure();

List<int> randomBytes(int n) => [for (var i = 0; i < n; i++) _rand.nextInt(256)];

String randomHex(int bytes) =>
    randomBytes(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 測試碼：GM + 10 碼，拆成 GMXX-XXXX-XXXX。
/// 字母表去掉 0/O/1/I/L 這些會看錯的字，31 個字元 × 10 位 ≈ 2^49 種，
/// 加上啟用 API 的限流，用猜的不可能猜中。
String newBetaCode() {
  const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  final s = List.generate(10, (_) => alphabet[_rand.nextInt(alphabet.length)]).join();
  return 'GM${s.substring(0, 2)}-${s.substring(2, 6)}-${s.substring(6, 10)}';
}
