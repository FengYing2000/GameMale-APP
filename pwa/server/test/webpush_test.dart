import 'package:pointycastle/export.dart';
import 'package:gm_server/vapid.dart';
import 'package:gm_server/webpush.dart';
import 'package:test/test.dart';

/// RFC 8291 Appendix A 的官方測試向量。
/// 原文為了排版把 base64url 折行加空白，這裡都已經接回去。
const _plaintext = 'When I grow up, I want to be a watermelon';
const _asPrivate = 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw';
const _asPublic = 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIg'
    'Dll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const _uaPublic = 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcx'
    'aOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4';
const _authSecret = 'BTBZMqHH6r4Tts7J_aSIgg';
const _salt = 'DGv6ra1nlYgDCS1FRnbzlw';

const _ecdhSecret = 'kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs';
const _prkKey = 'Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k';
const _ikm = 'S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg';
const _prk = '09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc';
const _cek = 'oIhVW04MRdy2XN9CiKLxTg';
const _nonce = '4h_95klXJ5E_qnoN';
const _header = 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml'
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const _ciphertext = '8pfeW0KbunFT06SuDKoJH9Ql87S1QUrdirN6GcG7sFz1y1sqLgVi1VhjVkHsUoEs'
    'bI_0LpXMuGvnzQ';

void main() {
  _curveValidation();

  group('RFC 8291 官方測試向量', () {
    late PushEncryption result;

    setUpAll(() {
      // 用固定的伺服器金鑰與 salt 才能重現 RFC 的結果；
      // 正式送訊息時這兩個都是每則隨機產生的。
      final serverKey =
          ECPrivateKey(bytesToBigInt(unb64u(_asPrivate)), p256);
      result = encryptPayload(
        plaintext: _plaintext.codeUnits,
        subscription: PushSubscription(
          endpoint: 'https://example.com/push',
          p256dh: unb64u(_uaPublic),
          auth: unb64u(_authSecret),
        ),
        salt: unb64u(_salt),
        serverKey: serverKey,
      );
    });

    test('由私鑰推出的伺服器公鑰要跟 RFC 給的一致', () {
      // 表頭裡帶的就是這把公鑰，推錯了收件端會解不開
      final derived = (p256.G * bytesToBigInt(unb64u(_asPrivate)))!;
      expect(b64u(encodePoint(derived)), _asPublic);
    });

    test('ECDH 共享密鑰', () => expect(b64u(result.ecdhSecret), _ecdhSecret));
    test('PRK_key（用 auth_secret 萃取）',
        () => expect(b64u(result.prkKey), _prkKey));
    test('IKM（綁定雙方公鑰後）', () => expect(b64u(result.ikm), _ikm));
    test('PRK（用 salt 萃取）', () => expect(b64u(result.prk), _prk));
    test('內容金鑰 CEK', () => expect(b64u(result.cek), _cek));
    test('NONCE', () => expect(b64u(result.nonce), _nonce));

    test('表頭剛好 86 bytes', () => expect(result.header.length, 86));
    test('表頭內容', () => expect(b64u(result.header), _header));
    test('密文', () => expect(b64u(result.ciphertext), _ciphertext));

    test('完整 body = 表頭 + 密文', () {
      // 注意是比位元組不是比 base64 字串：表頭 86 bytes 不是 3 的倍數，
      // 所以 b64u(表頭)+b64u(密文) 跟 b64u(表頭+密文) 並不相等。
      expect(result.body, <int>[...unb64u(_header), ...unb64u(_ciphertext)]);
    });
  });

  group('公鑰編解碼', () {
    test('65 bytes 未壓縮格式來回轉換不變', () {
      final raw = unb64u(_uaPublic);
      expect(encodePoint(decodePoint(raw)), raw);
    });

    test('長度不對要擋下來', () {
      expect(() => decodePoint(List.filled(64, 0)), throwsArgumentError);
    });

    test('沒有 0x04 開頭要擋下來', () {
      expect(() => decodePoint(List.filled(65, 0)), throwsArgumentError);
    });
  });

  group('base64url 無填充', () {
    test('編碼不留 =', () => expect(b64u([255, 254]), isNot(contains('='))));
    test('解碼補得回來', () {
      for (final n in [1, 2, 3, 4, 5, 16, 32, 65]) {
        final bytes = List<int>.generate(n, (i) => (i * 37) & 0xff);
        expect(unb64u(b64u(bytes)), bytes, reason: '$n bytes');
      }
    });
  });
}

void _curveValidation() {
  group('曲線驗證（RFC 8291 安全性考量：MUST）', () {
    test('RFC 給的真實公鑰在曲線上', () {
      expect(isOnCurve(decodePoint(unb64u(_uaPublic))), isTrue);
    });

    test('隨便湊的 65 bytes 要被擋下來', () {
      // 不驗的話這種點會構成 invalid curve attack
      for (final fill in [0, 1, 7, 0x55, 0xfe]) {
        final bogus = List<int>.filled(65, fill)..[0] = 0x04;
        expect(() => decodePoint(bogus), throwsArgumentError,
            reason: '整串 $fill');
      }
    });

    test('把合法公鑰的最後一個 byte 改掉就不在曲線上了', () {
      final raw = List<int>.from(unb64u(_uaPublic));
      raw[64] = raw[64] ^ 0x01;
      expect(() => decodePoint(raw), throwsArgumentError);
    });

    test('自己產的金鑰一定在曲線上', () {
      for (var i = 0; i < 5; i++) {
        final k = VapidKeys.generate();
        expect(isOnCurve(decodePoint(unb64u(k.publicKeyBase64))), isTrue);
      }
    });
  });
}
