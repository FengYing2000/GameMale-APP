import 'package:gm_server/rate_limit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter', () {
    test('同一來源超過上限就擋', () {
      final rl = RateLimiter(maxPerWindow: 3, window: const Duration(minutes: 1));
      expect(rl.allow('a'), isTrue);
      expect(rl.allow('a'), isTrue);
      expect(rl.allow('a'), isTrue);
      expect(rl.allow('a'), isFalse); // 第 4 個擋下
    });

    test('不同來源各自計算，不互相影響', () {
      final rl = RateLimiter(maxPerWindow: 1, window: const Duration(minutes: 1));
      expect(rl.allow('a'), isTrue);
      expect(rl.allow('b'), isTrue); // b 不受 a 影響
      expect(rl.allow('a'), isFalse);
    });

    test('視窗過了就恢復', () async {
      final rl =
          RateLimiter(maxPerWindow: 1, window: const Duration(milliseconds: 50));
      expect(rl.allow('a'), isTrue);
      expect(rl.allow('a'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(rl.allow('a'), isTrue);
    });
  });

  group('clientIp', () {
    test('取 X-Forwarded-For 的第一個（真實來源）', () {
      final r = Request('GET', Uri.parse('http://x/gm'),
          headers: {'x-forwarded-for': '1.2.3.4, 10.0.0.1'});
      expect(clientIp(r), '1.2.3.4');
    });

    test('退回 X-Real-IP', () {
      final r = Request('GET', Uri.parse('http://x/gm'),
          headers: {'x-real-ip': '5.6.7.8'});
      expect(clientIp(r), '5.6.7.8');
    });

    test('兩者都沒有回 unknown', () {
      final r = Request('GET', Uri.parse('http://x/gm'));
      expect(clientIp(r), 'unknown');
    });
  });
}
