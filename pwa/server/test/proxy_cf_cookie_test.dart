import 'package:gm_server/forum_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// 轉發對 cookie 只做兩件事：剝掉我們自己的 `gm_session`、把論壇 cookie
/// 原樣帶過去。
///
/// （曾經在這裡補一顆 `TVj0_2132_cloudflare_check=1` 繞 Turnstile，論壇
/// 2026-09-09 改插件機制後那招失效——改成只認真正已登入的 session，
/// 網頁版改走管理員給的 UserAgent 白名單，補 cookie 已移除。）
void main() {
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

  group('轉發的 cookie 處理', () {
    test('論壇 cookie 原樣帶過去', () async {
      final sent =
          await forwardedCookie('TVj0_2132_auth=abc; TVj0_2132_saltkey=xyz');
      expect(sent, contains('TVj0_2132_auth=abc'));
      expect(sent, contains('TVj0_2132_saltkey=xyz'));
    });

    test('我們自己的 gm_session 不會送到論壇', () async {
      final sent =
          await forwardedCookie('gm_session=secret; TVj0_2132_auth=abc');
      expect(sent, isNot(contains('gm_session')));
      expect(sent, contains('TVj0_2132_auth=abc'));
    });

    test('沒帶 cookie 就不硬補（不再補 cloudflare_check）', () async {
      final sent = await forwardedCookie(null);
      expect(sent, anyOf(isNull, isEmpty));
    });
  });
}
