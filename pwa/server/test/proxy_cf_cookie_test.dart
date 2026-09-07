import 'package:gm_api/http.dart';
import 'package:gm_server/forum_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// 轉發時要補上論壇 Turnstile 外掛的通關 cookie，網頁版才不會撞驗證頁。
///
/// 那個外掛只看這顆 cookie 在不在、值是不是字面的 1（不綁 session/IP/UA），
/// 所以補上固定值就等於通過——瀏覽器這邊沒辦法自己解 Turnstile。
void main() {
  /// 跑一次轉發，回傳實際送到論壇的 cookie 標頭
  Future<String?> forwardedCookie(String? incoming) async {
    String? seen;
    final client = MockClient((req) async {
      seen = req.headers['cookie'];
      return http.Response('ok', 200);
    });
    final proxy = ForumProxy(client: client);
    final req = Request(
      'GET',
      Uri.parse('https://852111.xyz/gm/forum.php?mobile=2'),
      headers: {if (incoming != null) 'cookie': incoming},
    );
    // server.dart 是用 change(path: 'gm') 把前綴剝掉後才交給 handle 的
    await proxy.handle(req.change(path: 'gm'));
    return seen;
  }

  group('轉發要補上 Turnstile 通關 cookie', () {
    test('瀏覽器沒帶任何 cookie 也要補上', () async {
      final sent = await forwardedCookie(null);
      expect(sent, '$kCfPassCookie=$kCfPassValue');
    });

    test('帶了論壇 cookie 就接在後面，原本的要留著', () async {
      final sent = await forwardedCookie(
        'TVj0_2132_auth=abc; TVj0_2132_saltkey=xyz',
      );
      expect(sent, contains('TVj0_2132_auth=abc'));
      expect(sent, contains('TVj0_2132_saltkey=xyz'));
      expect(sent, contains('$kCfPassCookie=$kCfPassValue'));
    });

    test('瀏覽器已經帶了通關 cookie 就不重複補', () async {
      final sent = await forwardedCookie(
        '$kCfPassCookie=$kCfPassValue; TVj0_2132_auth=abc',
      );
      final hits = kCfPassCookie.allMatches(sent ?? '').length;
      expect(hits, 1, reason: '$kCfPassCookie 只能出現一次');
    });

    test('我們自己的 gm_session 不會送到論壇', () async {
      final sent = await forwardedCookie('gm_session=secret; TVj0_2132_auth=abc');
      expect(sent, isNot(contains('gm_session')));
      expect(sent, contains('TVj0_2132_auth=abc'));
      expect(sent, contains('$kCfPassCookie=$kCfPassValue'));
    });
  });
}
