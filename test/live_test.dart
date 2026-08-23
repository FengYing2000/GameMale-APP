// 對真實論壇跑端對端測試（會發出真實請求）。
//
//   $env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
//   flutter test test/live_test.dart --dart-define=GM_COOKIE="$env:GM_COOKIE"
//
// 沒帶 cookie 就整組略過，CI 不會因此失敗。
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/api/discuz.dart' as api;
import 'package:gamemale/api/http.dart';
import 'package:gamemale/api/models.dart';
import 'package:gamemale/api/register.dart' as register;
import 'package:gamemale/api/search.dart' as search;
import 'package:gamemale/api/smilies.dart' as smilies;
import 'package:gamemale/api/space.dart' as space;

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
    final s = d.sign;
    // ignore: avoid_print
    print('  ${d.groups.length} 個分類、${forums.length} 個板塊'
        '${s == null ? '' : '；簽到 ${s.signed ? '已完成' : '未完成'}'
            '，經驗 ${s.maxed ? '${s.exp} (已滿級)' : '${s.exp}/${s.expMax}'}'
            '，進度 ${s.percent.toStringAsFixed(0)}%'}');
    if (s != null && !s.maxed) expect(s.expMax, greaterThan(0));
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

  test('個人資料抓得到暱稱與積分，且不混進自己的資料', () async {
    final me = await api.checkSession();
    final other = await api.fetchProfile(738943);
    expect(other.name, isNotEmpty);
    expect(other.credits, isNotEmpty);
    expect(other.isSelf, isFalse, reason: '別人的頁面不該被判成自己的');
    expect(other.name, isNot(equals(me!.name)), reason: '抓到的是自己的資料就代表解析錯了');
    // ignore: avoid_print
    print('  ${other.name} (${other.level})：'
        '${other.credits.take(3).map((c) => '${c.name} ${c.value}').join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('記錄廣場抓得到記錄', () async {
    final d = await api.fetchDoing();
    expect(d.items, isNotEmpty);
    expect(d.items.every((x) => x.doid > 0 && x.message.isNotEmpty), isTrue);
    // ignore: avoid_print
    print('  ${d.items.length} 則，最新：${d.items.first.name} — ${d.items.first.message}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('抓得到積分名稱對照（勳章顯示要用）', () async {
    await api.fetchIndex();
    final changes = await api.consumeCreditNotice();
    // ignore: avoid_print
    print('  目前 cookie 帶的積分變化：'
        '${changes.isEmpty ? '(無)' : changes.join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));


  test('評分表單抓得到可用項目與理由', () async {
    final f = await api.fetchRateForm(fid: 150, tid: 194078, pid: 7282915);
    // ignore: avoid_print
    print('  可評項目：${f.options.map((o) => '${o.name}(${o.range}, 剩${o.remaining})').join('、')}');
    // ignore: avoid_print
    print('  可選理由：${f.reasons.take(4).join('、')}');
    if (f.canRate) {
      expect(f.formhash, isNotEmpty);
      expect(f.tid, '194078');
      expect(f.pid, '7282915');
      for (final o in f.options) {
        expect(o.field.startsWith('score'), isTrue);
        expect(o.name, isNotEmpty);
        expect(o.choices, isNotEmpty, reason: '每項都該有可選的加分值');
      }
    } else {
      // ignore: avoid_print
      print('  → 目前不能評分：${f.message}');
    }
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('評分紀錄讀得出來', () async {
    final list = await api.fetchRatings(tid: 194078, pid: 7282915);
    expect(list, isNotEmpty);
    expect(list.every((r) => r.credits.isNotEmpty && r.name.isNotEmpty), isTrue);
    // ignore: avoid_print
    print('  合併後 ${list.length} 筆，例如：${list.first.name} '
        '${list.first.credits.join('、')}'
        '${list.first.reason.isEmpty ? '' : '（${list.first.reason}）'}');
  }, timeout: const Timeout(Duration(seconds: 40)));


  test('五種搜尋分類都拿得到結果', () async {
    await api.fetchIndex();   // 先取得 formhash
    for (final scope in SearchScope.values) {
      final r = await search.search('游戏', scope: scope);
      // ignore: avoid_print
      print('  ${scope.label.padRight(4)} ${r.hits.length} 筆'
          '${r.hits.isEmpty ? '（${r.message}）' : '，例如：${r.hits.first.title}'}');
      await Future<void>.delayed(const Duration(seconds: 2));  // 論壇有搜尋頻率限制
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('我的回覆抓得到資料', () async {
    final me = await api.checkSession();
    final r = await api.fetchMyPosts(me!.uid!, type: 'reply');
    expect(r.list, isNotEmpty, reason: '我的回覆不該是空的');
    expect(r.list.every((t) => t.tid > 0), isTrue);
    // ignore: avoid_print
    print('  我的回覆 ${r.list.length} 筆，例如：${r.list.first.title}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('個人資料（桌面模板）抓得到角色組、勳章、群組', () async {
    final p = await api.fetchProfile(610657);
    expect(p.name, isNotEmpty);
    expect(p.level, isNotEmpty, reason: '用戶組來自活躍概況');
    expect(p.credits.length, greaterThan(5));
    expect(p.medals, isNotEmpty);
    expect(p.stats, isNotEmpty);
    // ignore: avoid_print
    print('  ${p.name}｜${p.level}｜角色 ${p.roles.join('、')}'
        '｜勳章 ${p.medals.length}｜區塊 ${p.sections.map((s) => s.title).join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('個人空間七個子頁都解得出東西', () async {
    for (final tab in SpaceTab.values) {
      final d = await space.fetchSpace(610657, tab);
      expect(d.owner, isNotEmpty, reason: '${tab.label} 拿不到空間主人');
      expect(d.items, isNotEmpty, reason: '${tab.label} 沒有內容：${d.message}');
      final first = d.items.first.title;
      // ignore: avoid_print
      print('  ${tab.label} ${d.items.length} 筆，例如：'
          '${first.length > 24 ? first.substring(0, 24) : first}');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('表情清單抓得到全部分組', () async {
    final g = await smilies.fetchSmilies();
    expect(g.length, greaterThan(3));
    expect(g.every((x) => x.items.isNotEmpty), isTrue);
    // ignore: avoid_print
    print('  ${g.map((x) => '${x.name}(${x.items.length})').join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('桌面頁的額外資訊：回帖獎勵與附件', () async {
    final prize = await api.fetchThreadExtras(194186);
    expect(prize.prize, isNotNull, reason: '這帖有回帖獎勵');
    expect(prize.prize!.pool, isNotEmpty);
    expect(prize.prize!.rule, isNotEmpty,
        reason: '#pl_top 第一列是空的廣告列，不能抓到空字串');

    final att = await api.fetchThreadExtras(129896);
    expect(att.prize, isNull, reason: '這帖沒有回帖獎勵');
    expect(att.attachments, isNotEmpty, reason: '這帖有一個付費附件');
    // 檔名那段裡巢了提示框，抓錯會拿到上傳時間而不是檔案大小
    expect(att.attachments.first.info, contains('下载次数'));
    expect(att.attachments.first.needsPay, isTrue);
    // ignore: avoid_print
    print('  獎池 ${prize.prize!.pool}　附件 ${att.attachments.first.name}'
        '（${att.attachments.first.price}）');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('相冊內頁與日誌內頁解得出來', () async {
    final a = await space.fetchAlbum(691946, 5635);
    expect(a.photos, isNotEmpty);
    // 照片格是 ul.mlp，只寫 .ml 會把側欄小圖也算進來
    expect(a.photos.every((p) => p.thumb.startsWith('http')), isTrue);
    expect(a.photos.every((p) => !p.full.endsWith('.thumb.jpg')), isTrue);

    final b = await space.fetchBlog(610657, 148970);
    expect(b.title, isNotEmpty);
    expect(b.html, isNotEmpty);
    // ignore: avoid_print
    print('  相冊 ${a.title} ${a.photos.length} 張｜日誌 ${b.title}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('版塊篩選：投票／懸賞／排序／時間都會改變結果', () async {
    Future<List<int>> ids(ForumQuery q) async =>
        (await api.fetchForum(150, query: q)).list.map((t) => t.tid).toList();

    final all = await ids(const ForumQuery());
    final poll = await ids(const ForumQuery(special: 'poll'));
    final reward = await ids(const ForumQuery(special: 'reward'));
    final byViews = await ids(const ForumQuery(orderby: 'views'));
    final week = await ids(const ForumQuery(dateline: 604800));

    expect(all, isNotEmpty);
    expect(poll, isNotEmpty);
    expect(reward, isNotEmpty);
    expect(poll, isNot(equals(all)));
    expect(reward, isNot(equals(poll)));
    expect(byViews, isNot(equals(all)));
    expect(week, isNotEmpty);
    // ignore: avoid_print
    print('  全部 ${all.length}｜投票 ${poll.length}｜懸賞 ${reward.length}'
        '｜依查看 ${byViews.length}｜一週 ${week.length}');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('authorid 判斷有沒有回過帖', () async {
    // 回過的帖會正常回內容，沒回過的論壇直接給「未定义操作」
    Future<bool> replied(int tid) async {
      final html = await Api.instance
          .get('forum.php?mod=viewthread&tid=$tid&authorid=677863');
      return !(html.contains('未定义操作') || html.contains('未定義操作'));
    }

    expect(await replied(194186), isTrue, reason: '這帖回過');
    expect(await replied(194170), isFalse, reason: '這帖沒回過');
  }, timeout: const Timeout(Duration(seconds: 60)));

  // 這個測試會清掉 cookie，一定要放在最後 —— 否則後面的測試都會以訪客身分跑，
  // 拿到的是登入頁而不是內容
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

  // 註冊只有訪客做得到 —— 已登入的話論壇會直接把你踢回首頁，
  // 所以這題要排在上面那個登出測試之後
  test('註冊問答讀得到題目，答錯會退回考卷', () async {
    final q = await register.fetchRegisterQuiz();
    expect(q.formhash, isNotEmpty);
    expect(q.questions, isNotEmpty);
    // 故意全選第一個選項，不會建立帳號
    final wrong = {
      for (final x in q.questions) x.field: [x.options.first.value]
    };
    final next = await register.submitRegisterQuiz(q.formhash, wrong);
    // 送出走桌面端點且會 302 —— Dart 的 HttpClient 不會自動跟隨 POST 轉址，
    // 沒補那一手的話這裡會拿到空字串
    expect(next.questions, isNotEmpty, reason: '答錯應該退回重新出題的考卷');
    // ignore: avoid_print
    print('  ${q.questions.length} 題｜公告：${q.notice}');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
