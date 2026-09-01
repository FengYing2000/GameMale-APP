import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart';

/// Web Push 訊息加密（RFC 8291）與 VAPID 授權（RFC 8292）。
///
/// pub.dev 上沒有現成的 Dart 實作，所以照規格自己寫。加密的每一個中間值
/// 都用 RFC 8291 Appendix A 的官方測試向量驗證過（見 `test/webpush_test.dart`）
/// —— 密碼學的東西不驗就等於沒寫。
///
/// 用 pointycastle 而不是 cryptography：後者在 Dart VM 上的 ECDH
/// (`DartEcdh.sharedSecretKey`) 只是個 `throw UnimplementedError()` 的空殼，
/// 它把 P-256 丟給瀏覽器或原生外掛做，伺服器端根本跑不起來。
///
/// 只實作 aes128gcm 這一種內容編碼——iOS 16.4+ Safari 和現代
/// Chrome/Firefox 都用它，舊的 aesgcm 已經沒有瀏覽器需要。

final ECDomainParameters p256 = ECDomainParameters('prime256v1');

/// base64url，去掉尾端的 `=`。Web Push 從頭到尾都用無填充版本。
String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64u(String s) {
  final t = s.trim();
  final pad = (4 - t.length % 4) % 4;
  return base64Url.decode(t + ('=' * pad));
}

BigInt bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b & 0xff);
  }
  return r;
}

/// 固定長度輸出。ECDH 的結果一定要補滿 32 bytes——
/// 前導 0 被吃掉會讓後面整串 HKDF 全部算錯，而且錯得很安靜。
Uint8List bigIntToBytes(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

SecureRandom _newRandom() {
  final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => math.Random.secure().nextInt(256)));
  return FortunaRandom()..seed(KeyParameter(seed));
}

/// 未壓縮的 P-256 公鑰：0x04 || X(32) || Y(32)，共 65 bytes
Uint8List encodePoint(ECPoint point) =>
    Uint8List.fromList(point.getEncoded(false));

ECPoint decodePoint(List<int> raw) {
  if (raw.length != 65 || raw[0] != 0x04) {
    throw ArgumentError('P-256 公鑰要是 65 bytes 的未壓縮格式（0x04 開頭），'
        '收到 ${raw.length} bytes');
  }
  final point = p256.curve.decodePoint(Uint8List.fromList(raw));
  if (point == null) throw ArgumentError('解不出 P-256 上的點');
  if (!isOnCurve(point)) {
    throw ArgumentError('公鑰不在 P-256 曲線上');
  }
  return point;
}

/// 確認這個點真的落在 P-256 上。
///
/// **這是必要的安全檢查，不是防呆**（RFC 8291 安全性考量那節寫的是 MUST）。
/// pointycastle 的 `decodePoint` 只把 x、y 讀出來，完全不驗曲線方程式，
/// 隨便塞 65 個位元組進去它都收。收下曲線外的點會構成 invalid curve attack：
/// 攻擊者反覆送特製的「公鑰」，可以從 ECDH 的結果一點一點推回我們的私鑰。
bool isOnCurve(ECPoint point) {
  final curve = p256.curve as fp.ECCurve;
  final q = curve.q;
  final x = point.x?.toBigInteger();
  final y = point.y?.toBigInteger();
  if (q == null || x == null || y == null) return false; // 無窮遠點
  if (x.isNegative || x >= q || y.isNegative || y >= q) return false;

  final a = curve.a!.toBigInteger()!;
  final b = curve.b!.toBigInteger()!;
  // y² ≡ x³ + ax + b  (mod q)
  return (y * y) % q == (x * x % q * x + a * x + b) % q;
}

Uint8List hmacSha256(List<int> key, List<int> data) {
  final mac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(key)));
  return mac.process(Uint8List.fromList(data));
}

/// HKDF。這裡要的長度都 <= 32，所以 expand 只需要跑一輪。
Uint8List hkdf(List<int> salt, List<int> ikm, List<int> info, int length) {
  final prk = hmacSha256(salt, ikm);
  final okm = hmacSha256(prk, <int>[...info, 0x01]);
  return Uint8List.fromList(okm.sublist(0, length));
}

/// 加密過程的每一步結果。中間值全部留著是為了能對著 RFC 的向量逐項比對——
/// 只驗最後的密文，一旦錯了根本不知道錯在哪一步。
class PushEncryption {
  const PushEncryption({
    required this.ecdhSecret,
    required this.prkKey,
    required this.ikm,
    required this.prk,
    required this.cek,
    required this.nonce,
    required this.header,
    required this.ciphertext,
  });

  final Uint8List ecdhSecret;
  final Uint8List prkKey;
  final Uint8List ikm;
  final Uint8List prk;
  final Uint8List cek;
  final Uint8List nonce;
  final Uint8List header;
  final Uint8List ciphertext;

  /// 真正 POST 出去的 body
  Uint8List get body => Uint8List.fromList(<int>[...header, ...ciphertext]);
}

/// 收件端的訂閱資料，就是瀏覽器 `PushSubscription.toJSON()` 給的東西
class PushSubscription {
  const PushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  /// 從瀏覽器送上來的 JSON 建立，順便驗格式。
  ///
  /// 一定要驗長度：p256dh 或 auth 少一個 byte 不會噴錯，只會安靜地
  /// 算出收件端解不開的密文——那種問題查起來很痛苦。
  factory PushSubscription.fromJson(Map<String, dynamic> j) {
    final endpoint = j['endpoint'];
    if (endpoint is! String || endpoint.isEmpty) {
      throw const FormatException('少了 endpoint');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.isScheme('https')) {
      throw const FormatException('endpoint 必須是 https 網址');
    }
    final keys = j['keys'];
    if (keys is! Map) throw const FormatException('少了 keys');

    Uint8List take(String name, int expected) {
      final v = keys[name];
      if (v is! String || v.isEmpty) throw FormatException('少了 keys.$name');
      final Uint8List bytes;
      try {
        bytes = unb64u(v);
      } on FormatException {
        throw FormatException('keys.$name 不是合法的 base64url');
      }
      if (bytes.length != expected) {
        throw FormatException(
            'keys.$name 應該是 $expected bytes，收到 ${bytes.length}');
      }
      return bytes;
    }

    final p256dh = take('p256dh', 65);
    // 順便確認這把公鑰真的在 P-256 曲線上——不驗會有 invalid curve attack
    try {
      decodePoint(p256dh);
    } on ArgumentError catch (e) {
      throw FormatException('keys.p256dh ${e.message}');
    }

    return PushSubscription(
      endpoint: endpoint,
      p256dh: p256dh,
      auth: take('auth', 16),
    );
  }

  /// push service 的網址，訊息就是 POST 到這裡
  final String endpoint;

  /// 收件端的 P-256 公鑰（65 bytes）
  final Uint8List p256dh;

  /// 收件端的驗證密鑰（16 bytes）
  final Uint8List auth;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'keys': {'p256dh': b64u(p256dh), 'auth': b64u(auth)},
      };
}

/// 依 RFC 8291 §3.4 把 payload 加密成 aes128gcm 的 body。
///
/// [salt] 與 [serverKey] 平常都留空（每則訊息隨機產生），
/// 只有跑 RFC 測試向量時才會指定。
PushEncryption encryptPayload({
  required List<int> plaintext,
  required PushSubscription subscription,
  List<int>? salt,
  ECPrivateKey? serverKey,
  int recordSize = 4096,
}) {
  final ECPrivateKey asPrivate;
  if (serverKey != null) {
    asPrivate = serverKey;
  } else {
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(p256), _newRandom()));
    asPrivate = gen.generateKeyPair().privateKey;
  }
  final asPublicPoint = (p256.G * asPrivate.d)!;
  final asPublicBytes = encodePoint(asPublicPoint);
  final uaPublicPoint = decodePoint(subscription.p256dh);

  final theSalt = Uint8List.fromList(salt ??
      List<int>.generate(16, (_) => math.Random.secure().nextInt(256)));

  // 1. ECDH：伺服器私鑰 × 收件端公鑰
  final agreement = ECDHBasicAgreement()..init(asPrivate);
  final ecdhSecret = bigIntToBytes(
      agreement.calculateAgreement(ECPublicKey(uaPublicPoint, p256)), 32);

  // 2. 用 auth_secret 把 ECDH 結果和雙方公鑰綁在一起（RFC 8291 §3.3）
  final prkKey = hmacSha256(subscription.auth, ecdhSecret);
  final keyInfo = <int>[
    ...utf8.encode('WebPush: info'),
    0x00,
    ...subscription.p256dh,
    ...asPublicBytes,
  ];
  final ikm = hmacSha256(prkKey, <int>[...keyInfo, 0x01]);

  // 3. 由 IKM 導出內容金鑰與 nonce（RFC 8188）
  final prk = hmacSha256(theSalt, ikm);
  final cek = hkdf(theSalt, ikm,
      <int>[...utf8.encode('Content-Encoding: aes128gcm'), 0x00], 16);
  final nonce = hkdf(
      theSalt, ikm, <int>[...utf8.encode('Content-Encoding: nonce'), 0x00], 12);

  // 4. 表頭：salt(16) || rs(4) || idlen(1) || 伺服器公鑰(65) = 86 bytes
  final header = BytesBuilder()
    ..add(theSalt)
    ..add(
        (ByteData(4)..setUint32(0, recordSize, Endian.big)).buffer.asUint8List())
    ..addByte(asPublicBytes.length)
    ..add(asPublicBytes);

  // 5. 最後一筆記錄要接分隔位元組 0x02，然後整包 AES-128-GCM
  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(cek), 128, nonce, Uint8List(0)));
  final ciphertext =
      gcm.process(Uint8List.fromList(<int>[...plaintext, 0x02]));

  return PushEncryption(
    ecdhSecret: ecdhSecret,
    prkKey: prkKey,
    ikm: ikm,
    prk: prk,
    cek: cek,
    nonce: nonce,
    header: header.toBytes(),
    ciphertext: ciphertext,
  );
}
