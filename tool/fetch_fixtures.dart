// 重新抓取測試用的頁面樣本。論壇改版時跑這支，再跑 flutter test 就知道哪些選擇器壞了。
//
//   $env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
//   $env:GM_UID = "733814"
//   dart run tool/fetch_fixtures.dart
//
// Cookie 只留在本機，test/fixtures/ 已經在 .gitignore 裡。
import 'dart:io';

const origin = 'https://www.gamemale.com';
const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

Future<void> main() async {
  final cookie = Platform.environment['GM_COOKIE'];
  final uid = Platform.environment['GM_UID'];
  if (cookie == null || uid == null) {
    stderr.writeln('請先設定環境變數 GM_COOKIE 與 GM_UID');
    exit(1);
  }

  final pages = <String, String>{
    'index.html': 'forum.php?mobile=2',
    'forum.html': 'forum.php?mod=forumdisplay&fid=57&mobile=2',
    'thread.html': 'forum.php?mod=viewthread&tid=129896&mobile=2',
    'guide.html': 'forum.php?mod=guide&view=newthread&mobile=2',
    'login.html': 'member.php?mod=logging&action=login&mobile=2',
    'me.html': 'home.php?mod=space&uid=$uid&do=profile&mycenter=1&mobile=2',
    'favorite.html': 'home.php?mod=space&uid=$uid&do=favorite&view=me&type=thread&mobile=2',
    'notice.html': 'home.php?mod=space&do=notice&view=mypost&forcemobile=1&mobile=2',
    'replyform.html': 'forum.php?mod=post&action=reply&fid=57&tid=129896&mobile=2',
    // 個人資料與個人空間只有桌面模板（帶 mobile=2 會被導到「無手機頁面」）
    'profile.html': 'home.php?mod=space&uid=610657&do=profile&mobile=no',
    'space_index.html': 'home.php?mod=space&uid=610657&do=index&mobile=no',
    'space_doing.html': 'home.php?mod=space&uid=610657&do=doing&view=me&mobile=no',
    'space_blog.html': 'home.php?mod=space&uid=610657&do=blog&view=me&mobile=no',
    'space_album.html': 'home.php?mod=space&uid=610657&do=album&view=me&mobile=no',
    'space_thread.html': 'home.php?mod=space&uid=610657&do=thread&view=me&mobile=no',
    'space_wall.html': 'home.php?mod=space&uid=610657&do=wall&mobile=no',
    'space_friend.html': 'home.php?mod=space&uid=610657&do=friend&view=me&mobile=no',
  };

  final dir = Directory('test/fixtures')..createSync(recursive: true);
  final client = HttpClient();

  for (final entry in pages.entries) {
    final req = await client.getUrl(Uri.parse('$origin/${entry.value}'));
    req.headers
      ..set('User-Agent', ua)
      ..set('Referer', '$origin/forum.php?mobile=2')
      // login.html 要的是「登出狀態」的表單，帶 cookie 會拿到歡迎頁
      ..set('Cookie', entry.key == 'login.html' ? '' : cookie);

    final res = await req.close();
    final body = await res.transform(const SystemEncoding().decoder).join();
    File('${dir.path}/${entry.key}').writeAsStringSync(body);

    final kb = (body.length / 1024).round().toString().padLeft(4);
    stdout.writeln('${res.statusCode}  $kb KB  ${entry.key}');
    await Future<void>.delayed(const Duration(milliseconds: 700)); // 別打太快
  }

  client.close();
  stdout.writeln('\nfixtures 更新完成，接著跑 flutter test');
}
