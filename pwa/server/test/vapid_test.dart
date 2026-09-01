import 'dart:convert';

import 'package:gm_server/vapid.dart';
import 'package:gm_server/webpush.dart';
import 'package:test/test.dart';

void main() {
  group('VAPID 金鑰', () {
    test('產出來的公鑰是 65 bytes 未壓縮格式', () {
      final raw = unb64u(VapidKeys.generate().publicKeyBase64);
      expect(raw.length, 65);
      expect(raw[0], 0x04);
    });

    test('私鑰存讀之後是同一把', () {
      final a = VapidKeys.generate();
      final b = VapidKeys.fromPrivateKey(a.privateKeyBase64);
      expect(b.publicKeyBase64, a.publicKeyBase64);
    });

    test('每次產的都不一樣', () {
      expect(VapidKeys.generate().publicKeyBase64,
          isNot(VapidKeys.generate().publicKeyBase64));
    });
  });

  group('VAPID JWT', () {
    final keys = VapidKeys.generate();
    final jwt = keys.signJwt(
      endpoint: 'https://web.push.apple.com/QRSTUV',
      subject: 'mailto:test@example.com',
    );

    test('是三段式的 JWT', () => expect(jwt.split('.').length, 3));

    test('標頭指定 ES256', () {
      final h = json.decode(utf8.decode(unb64u(jwt.split('.')[0])));
      expect(h['alg'], 'ES256');
      expect(h['typ'], 'JWT');
    });

    test('aud 只取 endpoint 的來源，不含路徑', () {
      final c = json.decode(utf8.decode(unb64u(jwt.split('.')[1])));
      expect(c['aud'], 'https://web.push.apple.com');
      expect(c['sub'], 'mailto:test@example.com');
    });

    test('exp 在未來，而且不超過 24 小時（規格上限）', () {
      final c = json.decode(utf8.decode(unb64u(jwt.split('.')[1])));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(c['exp'], greaterThan(now));
      expect(c['exp'], lessThanOrEqualTo(now + 24 * 3600));
    });

    test('簽章是固定長度 r||s 共 64 bytes，不是 DER', () {
      expect(unb64u(jwt.split('.')[2]).length, 64);
    });

    test('自己驗得過', () => expect(keys.verifyJwt(jwt), isTrue));

    test('被竄改就驗不過', () {
      final parts = jwt.split('.');
      final tampered = json.encode({'aud': 'https://evil.example', 'exp': 1});
      expect(
        keys.verifyJwt('${parts[0]}.${b64u(utf8.encode(tampered))}.${parts[2]}'),
        isFalse,
      );
    });

    test('別人的金鑰驗不過', () {
      expect(VapidKeys.generate().verifyJwt(jwt), isFalse);
    });

    test('s 一律正規化成低值', () {
      // 高 s 的簽章有些 push service 會拒收，所以每次都要normalize。
      // 連簽 20 次，s 都必須落在 n/2 以下。
      final half = p256.n >> 1;
      for (var i = 0; i < 20; i++) {
        final t = keys.signJwt(
            endpoint: 'https://example.com/$i', subject: 'mailto:a@b.c');
        final s = bytesToBigInt(unb64u(t.split('.')[2]).sublist(32));
        expect(s.compareTo(half), lessThanOrEqualTo(0), reason: '第 $i 次');
      }
    });
  });
}
