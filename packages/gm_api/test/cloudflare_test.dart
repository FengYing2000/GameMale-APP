import 'package:dio/dio.dart';
import 'package:gm_api/http.dart';
import 'package:test/test.dart';

/// 論壇 2026-09-05 開了全站 Cloudflare 挑戰。挑戰頁回的是 403，
/// 跟「沒有權限」同一個狀態碼——分不出來的話，使用者會拿到一個
/// 按了也沒用的「重試」，而真正該做的是去解一次驗證。
Response<dynamic> _res(int code, {Map<String, String> headers = const {}, String body = ''}) =>
    Response<dynamic>(
      requestOptions: RequestOptions(path: '/forum.php'),
      statusCode: code,
      data: body,
      headers: Headers.fromMap({
        for (final e in headers.entries) e.key: [e.value],
      }),
    );

void main() {
  group('認得出 Cloudflare 挑戰', () {
    test('cf-mitigated 標頭是最準的訊號', () {
      // 實測論壇開啟時回的就是這個
      expect(
        Api.isCloudflareChallenge(_res(403, headers: {
          'cf-mitigated': 'challenge',
          'server': 'cloudflare',
        })),
        isTrue,
      );
    });

    test('沒有那個標頭時比對內文特徵', () {
      expect(
        Api.isCloudflareChallenge(_res(403,
            headers: {'server': 'cloudflare'},
            body: '<html><head><title>Just a moment...</title>'
                '<script src="/cdn-cgi/challenge-platform/x.js"></script>')),
        isTrue,
      );
    });

    test('503 的挑戰也要認得', () {
      expect(
        Api.isCloudflareChallenge(
            _res(503, headers: {'cf-mitigated': 'challenge'})),
        isTrue,
      );
    });
  });

  group('不能把一般的 403 當成挑戰', () {
    test('論壇自己的權限不足', () {
      // 這種重試或登入才有用，跳去解驗證只會讓人更困惑
      expect(
        Api.isCloudflareChallenge(_res(403,
            headers: {'server': 'nginx'},
            body: '<div class="alert_error">您沒有權限訪問此版塊</div>')),
        isFalse,
      );
    });

    test('Cloudflare 擋下但不是挑戰（例如封鎖）', () {
      expect(
        Api.isCloudflareChallenge(_res(403,
            headers: {'server': 'cloudflare', 'cf-mitigated': 'block'},
            body: '<html>blocked</html>')),
        isFalse,
      );
    });

    test('404 / 500 不是挑戰', () {
      expect(Api.isCloudflareChallenge(_res(404)), isFalse);
      expect(
        Api.isCloudflareChallenge(
            _res(500, headers: {'server': 'cloudflare'})),
        isFalse,
      );
    });

    test('正常的 200 頁面就算提到那些字也不算', () {
      expect(
        Api.isCloudflareChallenge(_res(200,
            headers: {'server': 'cloudflare'},
            body: '有人在帖子裡貼了 challenge-platform 這個字')),
        isFalse,
      );
    });
  });
}
