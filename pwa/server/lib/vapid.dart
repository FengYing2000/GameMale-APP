import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'webpush.dart';

/// VAPID —— 應用伺服器的身分識別（RFC 8292）。
///
/// 這是 iOS 推播不用付費開發者帳號的關鍵：金鑰是自己產的，
/// 不需要跟 Apple 申請任何東西。push service 只認這把金鑰，
/// 用它來確認「這則推播真的是你的伺服器送的」。
class VapidKeys {
  const VapidKeys({required this.privateKey, required this.publicKey});

  /// 產一組新的。**產一次就要存起來**——換金鑰會讓所有既有訂閱失效，
  /// 使用者得重新授權一次通知。
  factory VapidKeys.generate() {
    final seed = Uint8List.fromList(
        List<int>.generate(32, (_) => math.Random.secure().nextInt(256)));
    final rnd = FortunaRandom()..seed(KeyParameter(seed));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(p256), rnd));
    final pair = gen.generateKeyPair();
    return VapidKeys(
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
    );
  }

  /// 從存下來的 base64url 私鑰還原（公鑰由私鑰推出來，不用另外存）
  factory VapidKeys.fromPrivateKey(String base64UrlPrivate) {
    final d = bytesToBigInt(unb64u(base64UrlPrivate));
    return VapidKeys(
      privateKey: ECPrivateKey(d, p256),
      publicKey: ECPublicKey((p256.G * d)!, p256),
    );
  }

  final ECPrivateKey privateKey;
  final ECPublicKey publicKey;

  /// 存進設定檔用的私鑰
  String get privateKeyBase64 => b64u(bigIntToBytes(privateKey.d!, 32));

  /// 前端 `applicationServerKey` 要用的公鑰（65 bytes 未壓縮）
  String get publicKeyBase64 => b64u(encodePoint(publicKey.Q!));

  /// 簽一張給 [endpoint] 用的 JWT。
  ///
  /// [subject] 要是 `mailto:` 或 https 網址——push service 出問題時
  /// 他們會照這個聯絡你，Firefox 的 push service 會擋掉沒填的。
  String signJwt({
    required String endpoint,
    required String subject,
    Duration validFor = const Duration(hours: 12),
  }) {
    final uri = Uri.parse(endpoint);
    final claims = {
      'aud': '${uri.scheme}://${uri.host}',
      'exp': DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000,
      'sub': subject,
    };
    final signingInput = '${b64u(utf8.encode(json.encode(
      {'typ': 'JWT', 'alg': 'ES256'},
    )))}.${b64u(utf8.encode(json.encode(claims)))}';

    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
    final sig =
        signer.generateSignature(Uint8List.fromList(utf8.encode(signingInput)))
            as ECSignature;

    // JWS 的 ES256 是固定長度的 r||s，各補滿 32 bytes（不是 DER）。
    // s 一律正規化成低值：有些 push service 會拒絕高 s 的簽章。
    final n = p256.n;
    final s = sig.s.compareTo(n >> 1) > 0 ? n - sig.s : sig.s;
    final raw = <int>[...bigIntToBytes(sig.r, 32), ...bigIntToBytes(s, 32)];

    return '$signingInput.${b64u(raw)}';
  }

  /// 驗自己簽的 JWT。正式流程用不到（是 push service 在驗），
  /// 但沒有官方測試向量可比對，至少要能證明簽出來的東西驗得過。
  bool verifyJwt(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return false;
    final raw = unb64u(parts[2]);
    if (raw.length != 64) return false;
    final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(false, PublicKeyParameter<ECPublicKey>(publicKey));
    return verifier.verifySignature(
      Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
      ECSignature(bytesToBigInt(raw.sublist(0, 32)),
          bytesToBigInt(raw.sublist(32))),
    );
  }
}
