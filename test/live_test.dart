// 對真實論壇跑端對端測試（會發出真實請求）。
//
//   $env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
//   flutter test test/live_test.dart --dart-define=GM_COOKIE="$env:GM_COOKIE"
//
// 沒帶 cookie 就整組略過，CI 不會因此失敗。
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/api/discuz.dart' as api;
import 'package:gamemale/api/http.dart';

const _cookie = String.fromEnvironment('GM_COOKIE');

void main() {
  if (_cookie.isEmpty) {
    test('略過端對端測試（未提供 GM_COOKIE）', () {}, skip: true);
    return;
  }

  setUpAll(() async {
    await Api.instance.seedCookies(_cookie);
  });

  test('session 有效且抓得到 uid', () async {
    final user = await api.checkSession();
    expect(user, isNotNull, reason: 'cookie 可能已過期');
    expect(user!.uid, greaterThan(0));
    // ignore: avoid_print
    print('  登入身分：${user.name} (uid ${user.uid})');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('首頁抓得到板塊與簽到狀態', () async {
    final d = await api.fetchIndex();
    final forums = d.groups.expand((g) => g.forums).toList();
    expect(d.groups, isNotEmpty);
    expect(forums.length, greaterThan(5));
    expect(forums.every((f) => f.fid > 0 && f.name.isNotEmpty), isTrue);
    // ignore: avoid_print
    print('  ${d.groups.length} 個分類、${forums.length} 個板塊'
        '${d.sign == null ? '' : '；簽到 ${d.sign!.signed ? '已完成' : '未完成'}'
            ' ${d.sign!.exp}/${d.sign!.expMax}'}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('板塊列表抓得到主題', () async {
    final f = await api.fetchForum(57);
    expect(f.name, isNotEmpty);
    expect(f.list, isNotEmpty);
    expect(f.list.every((t) => t.tid > 0 && t.title.isNotEmpty), isTrue);
    expect(f.pager.total, greaterThan(1));
    // ignore: avoid_print
    print('  ${f.name}：${f.list.length} 筆 / 共 ${f.pager.total} 頁'
        '；分類 ${f.types.length} 個、子版塊 ${f.subforums.length} 個');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('帖子內頁抓得到樓層與內容', () async {
    final f = await api.fetchForum(57);
    final t = await api.fetchThread(f.list.first.tid);
    expect(t.title, isNotEmpty);
    expect(t.posts, isNotEmpty);
    expect(t.posts.every((p) => p.html.isNotEmpty), isTrue);
    expect(t.posts.every((p) => !p.html.contains('<script')), isTrue);
    // ignore: avoid_print
    print('  《${t.title}》${t.posts.length} 樓 / 共 ${t.pager.total} 頁');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('導讀抓得到最新主題', () async {
    final g = await api.fetchGuide();
    expect(g.list, isNotEmpty);
    // ignore: avoid_print
    print('  導讀 ${g.list.length} 筆，最新：${g.list.first.title}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('通知頁解析得出項目', () async {
    final n = await api.fetchNotice();
    // ignore: avoid_print
    print('  通知 ${n.items.length} 則${n.message == null ? '' : '（${n.message}）'}');
    for (final item in n.items.take(3)) {
      expect(item.text, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('收藏頁解析得出 favid', () async {
    final user = await api.checkSession();
    final fav = await api.fetchFavorites(user!.uid!);
    // ignore: avoid_print
    print('  收藏 ${fav.list.length} 筆');
    for (final t in fav.list.take(3)) {
      expect(t.tid, greaterThan(0));
      expect(t.title, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(seconds: 40)));

  // 已登入時論壇不回登入表單，只回「欢迎您回来」提示頁。
  // 登出狀態下的表單解析由 parse_test 的 login.html 樣本覆蓋。
  test('登入頁不會讓解析器爆掉', () async {
    final m = await api.loginMeta();
    // ignore: avoid_print
    print('  formhash=${m.formhash.isEmpty ? '(無)' : m.formhash}'
        '  loginhash=${m.loginhash.isEmpty ? '(無)' : m.loginhash}'
        '  需要驗證碼=${m.needSeccode}');
    if (m.loginhash.isEmpty) {
      // ignore: avoid_print
      print('  → 目前是已登入狀態，論壇未提供登入表單（預期行為）');
    } else {
      expect(m.formhash, isNotEmpty);
      expect(m.needSeccode, isTrue);
      expect(m.seccodeImage, isNotNull);
      expect(m.seccodeImage!.length, greaterThan(200));
    }
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('登出後能重新取得登入表單與驗證碼', () async {
    await Api.instance.clearCookies();
    final m = await api.loginMeta();
    expect(m.formhash, isNotEmpty, reason: '登出狀態應該要有 formhash');
    expect(m.loginhash, isNotEmpty, reason: '登出狀態應該要有 loginhash');
    expect(m.needSeccode, isTrue);
    expect(m.seccodeImage, isNotNull, reason: '驗證碼圖必須帶 session cookie 才抓得到');
    expect(m.seccodeImage!.length, greaterThan(200));
    // ignore: avoid_print
    print('  loginhash=${m.loginhash}  驗證碼圖 ${m.seccodeImage!.length} bytes');
  }, timeout: const Timeout(Duration(seconds: 40)));

}
