import 'dart:convert';
import 'dart:typed_data';

import 'package:gm_server/secret_box.dart';
import 'package:test/test.dart';

void main() {
  final box = SecretBox.fromBase64(SecretBox.generateKey());

  group('加解密', () {
    test('原封不動轉回來', () {
      for (final s in [
        'cGVfNTZjMV9zYWx0abc=',
        '中文也要沒問題',
        '',
        'a' * 5000,
        'emoji 🎉 與換行\n\t制表',
      ]) {
        expect(box.open(box.seal(s)), s, reason: '長度 ${s.length}');
      }
    });

    test('同一段明文每次加出來都不一樣（nonce 不重複用）', () {
      final seen = {for (var i = 0; i < 30; i++) box.seal('same-cookie')};
      expect(seen.length, 30, reason: 'nonce 重複用會直接洩漏明文');
    });

    test('密文長度 = 12 nonce + 明文 + 16 標籤', () {
      final raw = base64.decode(box.seal('12345'));
      expect(raw.length, 12 + 5 + 16);
    });
  });

  group('金鑰', () {
    test('產出來是 32 bytes', () {
      expect(base64.decode(SecretBox.generateKey()).length, 32);
    });

    test('每次產的都不同', () {
      expect(SecretBox.generateKey(), isNot(SecretBox.generateKey()));
    });

    test('長度不對要當場擋下來', () {
      expect(() => SecretBox(Uint8List(16)), throwsArgumentError);
      expect(() => SecretBox(Uint8List(31)), throwsArgumentError);
    });

    test('尾巴的 = 被砍掉時要講得出人話', () {
      // 用 shell 的 cut -d= 取金鑰就會踩到這個，錯誤訊息要指得出方向
      final key = SecretBox.generateKey();
      expect(
        () => SecretBox.fromBase64(key.replaceAll('=', '')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('別把金鑰的長度錯誤留到解密才發現', () {
      // 設定填錯時要在啟動就炸，不要等到有人登入才出事
      expect(() => SecretBox.fromBase64(base64.encode(List.filled(8, 1))),
          throwsArgumentError);
    });
  });

  group('竄改與錯誤金鑰要被擋下', () {
    test('換一把金鑰解不開', () {
      final other = SecretBox.fromBase64(SecretBox.generateKey());
      expect(() => other.open(box.seal('secret')), throwsFormatException);
    });

    test('改掉密文任何一個 byte 都解不開', () {
      final raw = base64.decode(box.seal('tamper-me-please'));
      for (final i in [0, 5, 12, 20, raw.length - 1]) {
        final bad = Uint8List.fromList(raw)..[i] ^= 0x01;
        expect(() => box.open(base64.encode(bad)), throwsFormatException,
            reason: '第 $i 個 byte');
      }
    });

    test('太短的輸入不會讓它爆成別種例外', () {
      for (final s in ['', 'AAAA', base64.encode(List.filled(20, 0))]) {
        expect(() => box.open(s), throwsFormatException);
      }
    });

    test('根本不是 base64 也要好好報錯', () {
      expect(() => box.open('這不是 base64!!'), throwsFormatException);
    });
  });
}
