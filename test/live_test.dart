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
import 'package:gamemale/api/group.dart' as group;
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

  test('勳章的等級、名稱、說明、加成要分得開', () async {
    final p = await api.fetchProfile(678084);
    expect(p.medals, isNotEmpty);
    // tip 裡等級和名字之間沒有空白，硬切正則會黏成「Max黑暗之魂系列」
    expect(p.medals.every((m) => !m.name.startsWith('等')), isTrue);
    expect(p.medals.any((m) => m.level.isNotEmpty), isTrue);
    expect(p.medals.every((m) => !m.name.contains(m.level) || m.level.isEmpty),
        isTrue);
    expect(p.medals.any((m) => m.effects.isNotEmpty), isTrue,
        reason: '萨菲罗斯那張有「回帖 血液 +1」');
    // ignore: avoid_print
    print('  ${p.medals.map((m) => '[${m.level}]${m.name}').join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('日誌內頁有表態、表態者、評論、作者其他日誌', () async {
    final b = await space.fetchBlog(610657, 148970);
    expect(b.reactions, isNotEmpty);
    expect(b.reactions.every((r) => r.name.isNotEmpty), isTrue);
    expect(b.reactedBy, isNotEmpty);
    expect(b.comments, isNotEmpty);
    expect(b.comments.every((c) => c.author.isNotEmpty), isTrue);
    expect(b.otherPosts, isNotEmpty);
    // ignore: avoid_print
    print('  表態 ${b.reactions.length} 種｜表態者 ${b.reactedBy.length}'
        '｜評論 ${b.comments.length}｜其他日誌 ${b.otherPosts.length}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('桌面首頁補得到手機版漏掉的子版塊', () async {
    final map = await api.fetchIndexSubforums();
    expect(map, isNotEmpty);
    // 勳章公會(128) 的「勳章博物館」(138) 手機模板整條沒有
    expect(map[128], isNotNull, reason: '勳章公會應該要有子版塊');
    expect(map[128]!.any((s) => s.fid == 138), isTrue);
    // ignore: avoid_print
    print('  ${map.length} 個版塊有子版塊；勳章公會 → '
        '${map[128]!.map((s) => s.name).join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('投票投過之後要顯示結果，不是「不開放作答」', () async {
    final t = await api.fetchThread(189088);
    final p = t.poll;
    expect(p, isNotNull);
    expect(p!.voted, isTrue, reason: '這帖已經投過了');
    expect(p.votable, isFalse);
    expect(p.status, contains('投过票'));
    expect(p.options, isNotEmpty);
    expect(p.options.every((o) => o.percent.isNotEmpty), isTrue);
    expect(p.options.any((o) => o.votes > 0), isTrue);
    // ignore: avoid_print
    print('  ${p.status}｜${p.options.length} 個選項，'
        '例如 ${p.options.first.text} ${p.options.first.percent}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('附件不列圖片，只列真正的檔案', () async {
    final e = await api.fetchThreadExtras(129896);
    expect(e.attachments, isNotEmpty);
    // 圖片已經在內文顯示了，不該再列一次
    expect(e.attachments.every((a) => !a.icon.contains('filetype/image')), isTrue);
    // ignore: avoid_print
    print('  ${e.attachments.map((a) => a.name).join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('群組只有桌面模板，走 /f/ 會是空的', () async {
    final open = await group.fetchGroup(116);
    expect(open.name, isNotEmpty);
    expect(open.threads, isNotEmpty, reason: '這個群組看得到主題');

    final closed = await group.fetchGroup(61);
    expect(closed.name, isNotEmpty, reason: '沒加入也該讀得到群組名');
    expect(closed.threads, isEmpty);
    expect(closed.message, isNotNull);

    // 群組首頁的分類底下有一整片群組（推薦只有幾個，分類才多）
    final idx = await group.fetchGroupIndex();
    final total = idx.categories.expand((c) => c.groups).length;
    expect(total, greaterThan(10));
    // ignore: avoid_print
    print('  ${open.name} ${open.threads.length} 篇｜分類群組 $total 個');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('簽到頁解得出等級與統計', () async {
    final d = await api.fetchSignPage();
    expect(d.stats, isNotEmpty, reason: '今日排名／連續／累計');
    expect(d.stats.every((s) => s.label.isNotEmpty && s.value.isNotEmpty), isTrue);
    expect(d.level, isNotEmpty);
    // 有結構化欄位就不該再倒整段 HTML（會把頁尾與側邊導覽畫進去）
    expect(d.html, isEmpty);
    // ignore: avoid_print
    print('  ${d.level}｜${d.stats.map((s) => '${s.label} ${s.value}').join('　')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('收藏清單帶得回 favid，才取消得掉', () async {
    final r = await api.fetchFavorites(677863);
    expect(r.list, isNotEmpty);
    expect(r.list.every((t) => t.favid != null && t.favid! > 0), isTrue,
        reason: '沒有 favid 就只能加不能減');
    // ignore: avoid_print
    print('  第一筆 tid=${r.list.first.tid} favid=${r.list.first.favid}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('日誌廣場三種視角都拿得到內容', () async {
    for (final v in blogViews) {
      final d = await space.fetchBlogList(v.key);
      expect(d.items, isNotEmpty, reason: '${v.name} 沒有內容：${d.message}');
      expect(d.items.every((i) => i.title.isNotEmpty), isTrue);
      // ignore: avoid_print
      print('  ${v.name} ${d.items.length} 篇');
    }
    // 隨便看看那頁論壇會列出分類
    final all = await space.fetchBlogList('all');
    expect(all.categories, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('日誌的表態按鈕帶得到連結', () async {
    final b = await space.fetchBlog(610657, 148970);
    expect(b.reactions, isNotEmpty);
    // 沒有連結就按不下去
    expect(b.reactions.every((r) => r.url.contains('ac=click')), isTrue);
    expect(b.reactions.every((r) => r.url.contains('hash=')), isTrue);
    // ignore: avoid_print
    print('  ${b.reactions.map((r) => r.name).join('、')}');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('購買附件的確認表單讀得到售價與餘額', () async {
    final e = await api.fetchThreadExtras(194170);
    final paid = e.attachments.where((a) => a.needsPay).firstOrNull;
    expect(paid, isNotNull);
    expect(paid!.aid, isNotNull, reason: '沒有 aid 就買不了');

    // 只讀表單，不送出 —— 送出會真的扣金幣
    final pay = await api.fetchAttachPay(paid.aid!, 194170);
    expect(pay.ready, isTrue);
    expect(pay.name, isNotEmpty);
    expect(pay.rows, isNotEmpty);
    expect(pay.rows.any((r) => r.label.contains('售价')), isTrue);
    expect(pay.rows.any((r) => r.label.contains('余额')), isTrue);
    // ignore: avoid_print
    print('  ${pay.name}｜${pay.rows.map((r) => '${r.label} ${r.value}').join('　')}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('三種附件都認得，圖片不列入', () async {
    // 已購買的（連結是 mod=attachment）
    final bought = await api.fetchThreadExtras(194000);
    expect(bought.attachments, hasLength(1));
    expect(bought.attachments.first.bought, isTrue);
    expect(bought.attachments.first.recordUrl, isNotEmpty);

    // 還沒買的（連結是 action=attachpay），而且是夾在內文中間的 span
    final unpaid = await api.fetchThreadExtras(194215);
    expect(unpaid.attachments, hasLength(1));
    expect(unpaid.attachments.first.bought, isFalse);
    expect(unpaid.attachments.first.needsPay, isTrue);

    // 「更多圖片」那七張是 dl.tattl.attm，不該被算成附件
    final images = await api.fetchThreadExtras(184725);
    expect(images.attachments, hasLength(1));
    expect(images.attachments.first.name, endsWith('.txt'));
    // ignore: avoid_print
    print('  已買 ${bought.attachments.first.name}｜'
        '未買 ${unpaid.attachments.first.price}｜'
        '排除圖片後 ${images.attachments.length} 個');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('附件內容自己解碼，不會變亂碼', () async {
    final e = await api.fetchThreadExtras(194000);
    final a = e.attachments.first;
    expect(a.bought, isTrue);
    final text = await api.fetchAttachmentText(a.url);
    // 伺服器送 octet-stream 又沒帶 charset，瀏覽器會猜錯編碼
    expect(text, contains('网盘'));
    expect(text, contains('http'));
    expect(text, isNot(contains('�')), reason: '有替換字元就是解錯編碼');
    // ignore: avoid_print
    print('  ${text.split('\n').first}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('只有上下頁的列表，頁數要跟著我們請求的走', () async {
    final p1 = await api.fetchMyPosts(677863, type: 'reply');
    final p2 = await api.fetchMyPosts(677863, type: 'reply', page: 2);
    expect(p1.pager.page, 1);
    expect(p2.pager.page, 2, reason: '照 DOM 算會一直停在第 1 頁');
    expect(p2.pager.hasPrev, isTrue);
    expect(p1.pager.numbered, isFalse);

    // 版塊有真的頁碼，那條路不能被改壞
    final f = await api.fetchForum(150, page: 2);
    expect(f.pager.page, 2);
    expect(f.pager.numbered, isTrue);
    expect(f.pager.total, greaterThan(100));
    // ignore: avoid_print
    print('  我的回覆 ${p2.pager.page}/${p2.pager.total}（無頁碼）'
        '｜版塊 ${f.pager.page}/${f.pager.total}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('記錄的回覆與刪除連結解得出來', () async {
    final all = await api.fetchDoing(view: 'all');
    expect(all.items.any((i) => i.comments.isNotEmpty), isTrue);
    // 記錄裡常夾表情圖，純文字會把它們吃掉
    expect(all.items.any((i) => i.html.contains('<img')), isTrue);
    // 別人的記錄不該給刪除連結
    expect(all.items.every((i) => i.deleteUrl.isEmpty), isTrue);

    final mine = await api.fetchDoing(view: 'me');
    expect(mine.items, isNotEmpty);
    expect(mine.items.every((i) => i.deleteUrl.isNotEmpty), isTrue);
    final withComment =
        mine.items.where((i) => i.comments.isNotEmpty).firstOrNull;
    expect(withComment, isNotNull);
    expect(withComment!.comments.first.deleteUrl, isNotEmpty);
    // 時間本來就帶括號，不該再被套一層
    expect(withComment.comments.first.time, isNot(startsWith('(')));
    // ignore: avoid_print
    print('  我的記錄 ${mine.items.length} 筆，可刪回覆 '
        '${mine.items.expand((i) => i.comments).where((c) => c.deleteUrl.isNotEmpty).length} 則');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('日誌的編輯／刪除／收藏連結與統計', () async {
    final mine = await space.fetchBlog(677863, 36332);
    expect(mine.editUrl, isNotEmpty);
    expect(mine.deleteUrl, isNotEmpty);
    expect(mine.favoriteUrl, isNotEmpty);

    final other = await space.fetchBlog(610657, 148970);
    expect(other.editUrl, isEmpty, reason: '別人的日誌不該有編輯連結');
    expect(other.stats, isNotEmpty);
    expect(other.stats.any((s) => s.label == '熱度'), isTrue);
    expect(other.stats.any((s) => s.label == '閱讀'), isTrue);
    // ignore: avoid_print
    print('  ${other.stats.map((s) => '${s.label} ${s.value}').join('　')}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('我的回覆帶得到版塊、回覆內容與樓層', () async {
    final r = await api.fetchGuideMine(type: 'reply');
    expect(r.list, isNotEmpty);
    expect(r.list.any((t) => t.forumName.isNotEmpty), isTrue);
    expect(r.list.any((t) => t.myReply.isNotEmpty), isTrue);
    final withPid = r.list.where((t) => t.myPid != null).firstOrNull;
    expect(withPid, isNotNull);

    // findpost 會轉到正確的頁，靠它跳到自己那一樓
    final page = await api.resolvePostPage(withPid!.tid, withPid.myPid!);
    expect(page, greaterThan(0));

    // 版塊篩選要真的縮小範圍
    final fid = r.list.firstWhere((t) => t.fid != null).fid!;
    final filtered = await api.fetchGuideMine(type: 'reply', fid: fid);
    expect(filtered.list, isNotEmpty);
    expect(filtered.list.every((t) => t.fid == null || t.fid == fid), isTrue);
    // ignore: avoid_print
    print('  ${r.list.length} 筆｜第一筆在 [${r.list.first.forumName}]'
        '｜跳到第 $page 頁｜篩 fid=$fid 剩 ${filtered.list.length} 筆');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('簽到說明三頁都解得出表格', () async {
    for (final p in signRulePages) {
      final r = await api.fetchSignRules(p.op);
      expect(r.tables.isNotEmpty || r.text.isNotEmpty, isTrue,
          reason: '${p.name} 什麼都沒解到');
      // 論壇每列開頭都塞一個空的圖示欄，不該留在資料裡
      for (final t in r.tables) {
        expect(t.rows.every((row) => row.isNotEmpty), isTrue);
      }
    }
    final rule = await api.fetchSignRules('rewardrule');
    expect(rule.intro, contains('奖励'));
    expect(rule.tables.length, greaterThanOrEqualTo(3));
    // ignore: avoid_print
    print('  ${rule.intro}｜${rule.tables.map((t) => '${t.title}(${t.rows.length})').join('、')}');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('我訂閱的專輯、版塊版規、收藏分類、簽到道具', () async {
    final c = await api.fetchCollections();
    expect(c, isNotEmpty);
    expect(c.every((x) => x.name.isNotEmpty && x.ctid > 0), isTrue);

    final e = await api.fetchForumExtras(206);
    expect(e.hasRules, isTrue);
    expect(e.favoriteUrl, isNotEmpty);
    // 版主只在版規那塊上面一行，整頁掃會把主題列表的作者也撈進來
    expect(e.moderators.length, lessThan(8));

    // 收藏之前只做了帖子與版塊
    for (final t in favoriteTypes) {
      final f = await api.fetchFavoriteList(677863, type: t.type);
      expect(f.items.every((i) => i.favid > 0 && i.title.isNotEmpty), isTrue,
          reason: '${t.name} 有缺欄位');
    }
    final threads = await api.fetchFavoriteList(677863, type: 'thread');
    expect(threads.items, isNotEmpty);
    expect(threads.items.every((i) => i.type == 'thread'), isTrue);

    final m = await api.fetchSignMagics();
    expect(m, isNotEmpty, reason: '補簽卡');
    expect(m.first.useUrl, isNotEmpty, reason: '要能直接補簽');
    expect(m.first.buyUrl, isNotEmpty, reason: '要能購買');
    // ignore: avoid_print
    print('  專輯 ${c.length}｜版主 ${e.moderators.map((x) => x.name).join('、')}'
        '｜道具 ${m.first.name}');
  }, timeout: const Timeout(Duration(seconds: 150)));

  test('附件的購買紀錄與原始位元組', () async {
    final ex = await api.fetchThreadExtras(194000);
    final a = ex.attachments.first;
    expect(a.aid, isNotNull);

    final pays = await api.fetchAttachPayments(a.aid!);
    expect(pays, isNotEmpty, reason: '這個附件有人買過');
    expect(pays.every((p) => p.user.isNotEmpty), isTrue);

    // 存檔要拿得到原始位元組
    final bytes = await api.fetchAttachmentBytes(a.url);
    expect(bytes.length, greaterThan(10));
    // ignore: avoid_print
    print('  ${pays.length} 筆紀錄，例如 ${pays.first.user}｜檔案 ${bytes.length} bytes');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('淘帖列表、專輯內頁、記錄廣場、簽到排行、道具彈窗', () async {
    // 淘帖列表（推薦）
    final idx = await api.fetchCollectionIndex();
    expect(idx.items, isNotEmpty);
    expect(idx.items.every((c) => c.ctid > 0 && c.name.isNotEmpty), isTrue);

    // 專輯內頁 + 收錄的主題
    final view = await api.fetchCollectionThreads(452);
    expect(view.name, isNotEmpty);
    expect(view.list, isNotEmpty);
    expect(view.list.every((t) => t.tid > 0 && t.title.isNotEmpty), isTrue);

    // 記錄廣場（桌面版才有內嵌回覆與時間）
    final doing = await api.fetchDoing(view: 'me');
    expect(doing.items, isNotEmpty);
    final cmts = doing.items.expand((x) => x.comments).toList();
    if (cmts.isNotEmpty) {
      expect(cmts.any((c) => c.time.isNotEmpty), isTrue, reason: '回覆要有時間');
      expect(cmts.every((c) => c.author.isNotEmpty), isTrue);
    }

    // 簽到排行
    final rank = await api.fetchSignRank();
    expect(rank, isNotEmpty);
    expect(rank.every((r) => r.name.isNotEmpty), isTrue);

    // 道具彈窗（補簽卡購買）
    final op = await api.fetchMagicOp(
        'home.php?mod=magic&action=shop&operation=buy&mid=k_misign:k_misign_bq');
    expect(op.ready, isTrue, reason: '要解析出購買表單');
    expect(op.fields['mid'], 'k_misign:k_misign_bq');

    // 淘帖表單（我的專輯清單）
    final add = await api.fetchAddThreadCollections(194232);
    expect(add.formhash, isNotEmpty);

    // ignore: avoid_print
    print('  專輯 ${idx.items.length}｜《${view.name}》${view.list.length} 帖'
        '｜記錄 ${doing.items.length}｜排行 ${rank.length}｜道具 ${op.name}');
  }, timeout: const Timeout(Duration(seconds: 150)));

  test('群組首頁、成員列表、我的群組', () async {
    final idx = await group.fetchGroupIndex();
    expect(idx.recommended, isNotEmpty, reason: '推薦群組');
    expect(idx.recommended.every((g) => g.fid > 0 && g.name.isNotEmpty), isTrue);
    expect(idx.categories, isNotEmpty, reason: '群組分類');
    expect(idx.categories.any((c) => c.groups.isNotEmpty), isTrue);
    expect(idx.ranking, isNotEmpty, reason: '積分排行');

    final members = await group.fetchGroupMembers(116);
    expect(members.members, isNotEmpty);
    expect(members.members.any((m) => m.title.contains('群主')), isTrue);

    // 我的群組（可能為空，只驗不丟例外）
    final mine = await group.fetchMyGroups(view: 'join');
    expect(mine, isA<List<GroupItem>>());

    // 群組詳情帶得出群主／是否已加入
    final g116 = await group.fetchGroup(116);
    expect(g116.name, isNotEmpty);
    expect(g116.master, isNotEmpty);

    // ignore: avoid_print
    print('  推薦 ${idx.recommended.length}｜分類 ${idx.categories.length}'
        '｜排行 ${idx.ranking.length}｜${g116.name} 群主 ${g116.master}'
        '｜成員 ${members.members.length}');
  }, timeout: const Timeout(Duration(seconds: 150)));

  test('道具售完時要回真正的訊息（不是「已送出」）', () async {
    // 補簽卡目前缺貨，送出購買不會扣錢，正好驗錯誤訊息有沒有抓到
    final op = await api.fetchMagicOp(
        'home.php?mod=magic&action=shop&operation=buy&mid=k_misign:k_misign_bq');
    expect(op.ready, isTrue);
    final r = await api.submitMagicOp(op);
    expect(r.ok, isFalse, reason: '缺貨應該是失敗');
    expect(r.message, contains('售完'));
    // ignore: avoid_print
    print('  ${r.message}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('我的回覆能數出真正的總頁數', () async {
    final first = await api.fetchGuideMine(type: 'reply', page: 1);
    if (first.pager.hasNext) {
      final total = await api.resolveGuideTotal(type: 'reply', fromPage: 2);
      expect(total, greaterThanOrEqualTo(2));
      // ignore: avoid_print
      print('  我的回覆共 $total 頁');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('紅點：頁首提醒選單解得出未讀數', () async {
    final b = await api.fetchBadges();
    expect(b.notice, greaterThanOrEqualTo(0));
    expect(b.pm, greaterThanOrEqualTo(0));
    // ignore: avoid_print
    print('  提醒未讀=${b.notice}｜私訊未讀=${b.pm}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('淘帖搜尋與單字搜尋', () async {
    // 淘帖搜尋（桌面）
    final c = await search.search('脚本', scope: SearchScope.collection);
    expect(c.hits, isNotEmpty, reason: '搜得到淘專輯');
    expect(c.hits.every((h) => h.url.contains('ctid=')), isTrue);

    // 論壇本身沒有 2 個字限制，一個字也搜得到
    final one = await search.search('猫', scope: SearchScope.forum);
    expect(one.hits, isNotEmpty, reason: '單字也搜得到帖子');
    // ignore: avoid_print
    print('  淘帖 ${c.hits.length} 個｜單字「猫」${one.hits.length} 筆');
  }, timeout: const Timeout(Duration(seconds: 90)));

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

  // 訪客看不到的東西要說清楚原因，這題也得排在登出之後
  test('訪客看鎖住的空間會拿到明確原因', () async {
    final album = await space.fetchSpace(691946, SpaceTab.album);
    expect(album.restricted, isTrue, reason: '相冊被隱私設定擋住');
    expect(album.message, contains('隐私'));

    final thread = await space.fetchSpace(691946, SpaceTab.thread);
    expect(thread.needsLogin, isTrue, reason: '主題會被轉去登入頁');
    // 轉址頁那句「如果您的浏览器没有自动跳转」不該直接丟給使用者看
    expect(thread.message, isNot(contains('跳轉')));
    expect(thread.message, isNot(contains('跳转')));
    // ignore: avoid_print
    print('  相冊：${album.message}');
    // ignore: avoid_print
    print('  主題：${thread.message}');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
