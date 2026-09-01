import 'package:gm_server/webpush.dart';
import 'package:test/test.dart';

/// 一組合法的訂閱資料，個別測試再去改壞其中一項。
Map<String, dynamic> _valid() => {
      'endpoint': 'https://web.push.apple.com/ABCDEF',
      'keys': {
        'p256dh': 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcx'
            'aOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
        'auth': 'BTBZMqHH6r4Tts7J_aSIgg',
      },
    };

void main() {
  group('訂閱資料解析', () {
    test('合法的收得下來', () {
      final s = PushSubscription.fromJson(_valid());
      expect(s.endpoint, 'https://web.push.apple.com/ABCDEF');
      expect(s.p256dh.length, 65);
      expect(s.auth.length, 16);
    });

    test('toJson 之後再讀回來是同一份', () {
      final a = PushSubscription.fromJson(_valid());
      final b = PushSubscription.fromJson(a.toJson());
      expect(b.endpoint, a.endpoint);
      expect(b.p256dh, a.p256dh);
      expect(b.auth, a.auth);
    });
  });

  group('壞掉的訂閱要擋下來', () {
    void rejects(String why, void Function(Map<String, dynamic>) breakIt) {
      test(why, () {
        final j = _valid();
        breakIt(j);
        expect(() => PushSubscription.fromJson(j), throwsFormatException);
      });
    }

    rejects('沒有 endpoint', (j) => j.remove('endpoint'));
    rejects('endpoint 是空字串', (j) => j['endpoint'] = '');
    rejects('endpoint 不是 https', (j) => j['endpoint'] = 'http://a.example/x');
    rejects('endpoint 不是字串', (j) => j['endpoint'] = 123);
    rejects('沒有 keys', (j) => j.remove('keys'));
    rejects('沒有 p256dh', (j) => (j['keys'] as Map).remove('p256dh'));
    rejects('沒有 auth', (j) => (j['keys'] as Map).remove('auth'));

    // 這兩個是最重要的：長度不對不會噴錯，只會安靜地產生
    // 收件端解不開的密文
    rejects('p256dh 長度不對',
        (j) => (j['keys'] as Map)['p256dh'] = b64u(List.filled(64, 4)));
    rejects('auth 長度不對',
        (j) => (j['keys'] as Map)['auth'] = b64u(List.filled(8, 1)));

    rejects('p256dh 不在 P-256 曲線上', (j) {
      final bogus = List<int>.filled(65, 7)..[0] = 0x04;
      (j['keys'] as Map)['p256dh'] = b64u(bogus);
    });
  });

  group('加密後的 body', () {
    final sub = PushSubscription.fromJson(_valid());

    test('每次的 salt 與伺服器金鑰都不同（不能重複用）', () {
      final a = encryptPayload(plaintext: [1, 2, 3], subscription: sub);
      final b = encryptPayload(plaintext: [1, 2, 3], subscription: sub);
      expect(a.header, isNot(b.header));
      expect(a.ciphertext, isNot(b.ciphertext));
    });

    test('body = 86 bytes 表頭 + 明文 + 分隔位元組 + 16 bytes 標籤', () {
      for (final n in [0, 1, 40, 500]) {
        final r = encryptPayload(
            plaintext: List.filled(n, 65), subscription: sub);
        expect(r.header.length, 86, reason: '$n bytes 的明文');
        expect(r.body.length, 86 + n + 1 + 16, reason: '$n bytes 的明文');
      }
    });
  });
}
