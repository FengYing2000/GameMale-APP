import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;

import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 全站共用的 formhash，換頁時順手更新
// formhash 綁 session，多帳號時絕對不能共用一份。實際存在 Api 實例上，
// 這裡只是轉發，好讓底下二十幾處 `_formhash` 的寫法都不用改。
String? get _formhash => Api.instance.formhash;
set _formhash(String? v) => Api.instance.formhash = v;

String? get formhash => _formhash;

String? _capture(dom.Document doc, [String? html]) {
  final f = formhashOf(doc, html);
  if (f != null && f.isNotEmpty) _formhash = f;
  return f;
}

/// 任何一頁被偵測到是訪客狀態時呼叫（session 過期）。由 SessionStore 掛上。
void Function()? onSessionLost;

/// 這些頁面本來就可能以訪客身分出現，不該觸發 session 失效
bool _guestAllowed(String url) =>
    url.contains('mod=logging') || url.contains('mod=seccode');

Future<dom.Document> _page(String url) async {
  final html = await Api.instance.get(url);
  final doc = toDoc(html);
  _capture(doc, html);
  _captureCreditNames(html);

  // 登入狀態只在冷啟動問一次是不夠的：cookie 隨時可能過期，
  // 不回報的話 UI 會一直停在「已登入」，但每個操作都被論壇擋下來。
  //
  // 但一定要用「看到登入入口」來判定，不能用「沒有登出連結」——
  // inajax 浮層片段兩者都沒有，會害使用者一點評分就被踢出登入狀態
  if (!_guestAllowed(url) && isGuestPage(doc)) {
    _formhash = null;
    onSessionLost?.call();
  }
  return doc;
}

Future<void> _ensureFormhash() async {
  if (_formhash == null) await fetchIndex();
}

/* ─────────────── 首頁：板塊列表 ─────────────── */

Future<IndexData> fetchIndex() async => parseIndex(await _page('forum.php'));

IndexData parseIndex(dom.Document doc) {
  final groups = <ForumGroup>[];

  for (final head in doc.querySelectorAll('.catlist > .subforumshow')) {
    final id = attr(head, 'href').replaceAll('#', '');
    final box = id.isNotEmpty ? doc.getElementById(id) : null;
    if (box == null) continue;

    final forums = <ForumItem>[];
    for (final li in box.querySelectorAll('li')) {
      final a = li.querySelector('a.forum_a');
      if (a == null) continue;
      final count = a.querySelector('.f_count');
      final nums = txt(count).split('/').map((s) => s.trim()).toList();
      final h3 = a.querySelector('h3');
      final name = h3 == null ? '' : txt(h3).replaceAll(txt(count), '').trim();
      // 簡介的 <p> 內有巢狀 <a>，HTML 解析時會被踢出 a.forum_a，所以從 li 找
      final p = li.querySelector('p');
      final desc = txt(p);

      // 子版塊寫在簡介裡：「子版块>>」後面接 forum-<fid>-1.html
      final subs = <SubForum>[];
      for (final link in p?.querySelectorAll('a[href*="forum-"]') ??
          const <dom.Element>[]) {
        final sid = int.tryParse(
            RegExp(r'forum-(\d+)').firstMatch(attr(link, 'href'))?.group(1) ?? '');
        if (sid == null) continue;
        final label = txt(link).replaceAll(RegExp(r'^\[|\]$'), '').trim();
        if (label.isEmpty) continue;
        if (subs.any((x) => x.fid == sid)) continue;
        subs.add(SubForum(fid: sid, name: sys(label)));
      }

      forums.add(ForumItem(
        fid: paramInt(attr(a, 'href'), 'fid') ?? 0,
        name: sys(name),
        icon: absolute(attr(li.querySelector('.f_icon img'), 'src')),
        threads: nums.isNotEmpty ? nums[0] : '',
        posts: attr(count?.querySelector('span[title]'), 'title').isNotEmpty
            ? attr(count?.querySelector('span[title]'), 'title')
            : (nums.length > 1 ? nums[1] : ''),
        desc: desc,
        descHtml: p == null ? '' : sanitizeContent(p),
        subforums: subs,
      ));
    }
    if (forums.isNotEmpty) {
      groups.add(
          ForumGroup(name: sys(txt(head.querySelector('h2'))), forums: forums));
    }
  }

  return IndexData(groups: groups, user: parseHeaderUser(doc), sign: parseSignWidget(doc));
}

/// 首頁的子版塊。手機模板只列出一部分（勳章公會的「勳章博物館」就漏了），
/// 桌面模板才完整。gzip 後約 35 KB，一個 App 生命週期抓一次就好。
Map<int, List<SubForum>>? _subforumCache;
Map<int, List<String>>? _moderatorCache;

/// 語言切換後，之前用舊語言 sys() 過的首頁快取要作廢，重抓才會跟著變
void clearIndexCache() {
  _subforumCache = null;
  _moderatorCache = null;
}

Future<Map<int, List<SubForum>>> fetchIndexSubforums({bool force = false}) async {
  if (!force && _subforumCache != null) return _subforumCache!;
  final doc = toDoc(await Api.instance.get('forum.php', desktop: true));
  final map = parseIndexSubforums(doc);
  if (map.isNotEmpty) _subforumCache = map;
  _moderatorCache = parseIndexModerators(doc);
  return map;
}

/// 首頁各版塊的版主。跟子版塊共用同一次桌面首頁抓取
Future<Map<int, List<String>>> fetchIndexModerators({bool force = false}) async {
  if (!force && _moderatorCache != null) return _moderatorCache!;
  await fetchIndexSubforums(force: force);
  return _moderatorCache ?? const {};
}

Map<int, List<SubForum>> parseIndexSubforums(dom.Document doc) {
  final out = <int, List<SubForum>>{};
  // 桌面首頁的版塊列有兩種殼：分類展開的 tr.fl_row，跟卡片式的 .fl_g
  final rows = [
    ...doc.querySelectorAll('.fl_row'),
    ...doc.querySelectorAll('.fl_g'),
  ];
  for (final row in rows) {
    final head = row.querySelector('h2 a') ?? row.querySelector('dt a');
    final fid = _fidOf(attr(head, 'href'));
    if (fid == null) continue;

    final subs = <SubForum>[];
    for (final a in row.querySelectorAll('a[href*="forum-"]')) {
      final sid = _fidOf(attr(a, 'href'));
      if (sid == null || sid == fid) continue;
      final name = txt(a).replaceAll(RegExp(r'^\[|\]$'), '').trim();
      if (name.isEmpty) continue;
      if (subs.any((x) => x.fid == sid)) continue;
      // 子版塊連結裡常帶一張小圖示
      subs.add(SubForum(
        fid: sid,
        name: sys(name),
        icon: absolute(attr(a.querySelector('img'), 'src')),
      ));
    }
    if (subs.isNotEmpty) out[fid] = subs;
  }
  return out;
}

/// 首頁各版塊的版主名單（桌面模板的「版主:」那一行）
Map<int, List<String>> parseIndexModerators(dom.Document doc) {
  final out = <int, List<String>>{};
  for (final td in doc.querySelectorAll('td, .fl_g, .fl_row')) {
    final head = td.querySelector('h2 a') ?? td.querySelector('dt a');
    final fid = _fidOf(attr(head, 'href'));
    if (fid == null) continue;
    // 版主寫在 <span class="xi2"> 裡，用 space-username 連結認人
    final mods = <String>[];
    for (final span in td.querySelectorAll('span.xi2')) {
      for (final a in span.querySelectorAll('a[href*="space-username"], a[href*="space-uid"]')) {
        final n = txt(a);
        if (n.isNotEmpty && !mods.contains(n)) mods.add(n);
      }
    }
    if (mods.isNotEmpty) out.putIfAbsent(fid, () => mods);
  }
  return out;
}

int? _fidOf(String href) =>
    int.tryParse(RegExp(r'forum-(\d+)').firstMatch(href)?.group(1) ?? '') ??
    paramInt(href, 'fid');

SessionUser parseHeaderUser(dom.Document doc) {
  final a = doc.querySelector('.topLogin') ?? doc.querySelector('a[href*="mycenter=1"]');
  final uid = paramInt(attr(a, 'href'), 'uid');
  final nameLink = doc.querySelector('.footer a[href*="mycenter=1"]');
  return SessionUser(
    uid: uid,
    name: txt(nameLink),
    avatar: uid == null ? '' : avatarUrl(uid),
    loggedIn: isLoggedIn(doc),
  );
}

/// 首頁頂端的 k_misign 簽到條
SignInfo? parseSignWidget(dom.Document doc) {
  final btn = doc.getElementById('signBtn');
  if (btn == null) return null;
  final nums = txt(doc.getElementById('fb_exp')).split('/');
  final width = attr(doc.getElementById('fb_current_progress'), 'style');
  final pct = RegExp(r'width\s*:\s*([\d.]+)%').firstMatch(width);

  final exp = nums.isNotEmpty ? digits(nums[0]) : 0;
  final expMax = nums.length > 1 ? digits(nums[1]) : 0;

  // 滿級時論壇把上限留空、進度條寫成 width:INF%（它自己除以零），
  // 照著解析會變成「1890 / 0」加上空的進度條
  final maxed = expMax == 0 && (exp > 0 || width.contains('INF'));

  return SignInfo(
    signed: btn.classes.contains('signed'),
    label: txt(btn),
    title: attr(btn, 'title').trim(),
    exp: exp,
    expMax: expMax,
    percent: maxed ? 100 : (pct == null ? 0 : (double.tryParse(pct.group(1)!) ?? 0)),
    maxed: maxed,
  );
}

/* ─────────────── 主題列表 ─────────────── */

Future<ForumData> fetchForum(
  int fid, {
  int page = 1,
  ForumQuery query = const ForumQuery(),
}) async {
  final q = <String, String>{'mod': 'forumdisplay', 'fid': '$fid'};
  if (page > 1) q['page'] = '$page';
  q.addAll(query.toParams());

  final doc = await _page('forum.php?${_qs(q)}');
  return parseForumFromDoc(doc, fid, page: page);
}

ForumData parseForumFromDoc(dom.Document doc, int fid, {int page = 1}) {
  return ForumData(
    fid: fid,
    name: sys(txt(doc.querySelector('header h1')).isNotEmpty
        ? txt(doc.querySelector('header h1'))
        : txt(doc.querySelector('.forumListHeader h3'))),
    meta: doc.querySelectorAll('.forumListHeader p span').map(txt).toList(),
    subforums: _parseSubforums(doc),
    types: doc.querySelectorAll('#thread_types li a').map((a) {
      final name = txt(a).replaceAll(RegExp(r'\(?\d+\)?$'), '').trim();
      return ThreadType(
        typeid: paramInt(attr(a, 'href'), 'typeid') ?? 0,
        name: name,
        count: txt(a.querySelector('.num')),
      );
    }).toList(),
    tabs: doc.querySelectorAll('.forumListTab li a').map((a) {
      final href = attr(a, 'href');
      return ForumTab(
        name: txt(a),
        cur: a.classes.contains('cur'),
        filter: param(href, 'filter') ?? '',
        orderby: param(href, 'orderby') ?? '',
        digest: param(href, 'digest') != null,
      );
    }).toList(),
    list: parseThreadList(doc),
    pager: parsePager(doc, current: page),
    message: noticeMessage(doc),
    requiresLogin: isLoginWall(doc),
  );
}

/// 子版塊在 #subMenu 的第一個 ul，但 package:html 沒有 :first-of-type。
/// 而且沒有子版塊時，第一個 ul 其實是主題分類（#thread_types），要排除。
List<SubForum> _parseSubforums(dom.Document doc) {
  final menu = doc.querySelector('#subMenu .subMenuBox') ?? doc.getElementById('subMenu');
  final ul = firstChildTag(menu, 'ul');
  if (ul == null || attr(ul, 'id') == 'thread_types') return const [];
  return ul
      .querySelectorAll('li a')
      .map((a) => SubForum(fid: paramInt(attr(a, 'href'), 'fid') ?? 0, name: txt(a)))
      .where((s) => s.fid > 0)
      .toList();
}

List<ThreadItem> parseThreadList(dom.Document doc) {
  final out = <ThreadItem>[];
  for (final li in doc.querySelectorAll('.threadlist li')) {
    // 「我的回覆」的連結是 mod=redirect&goto=findpost&ptid=…，
    // 只認 mod=viewthread + tid 會讓整頁被過濾成空的
    final a = li.querySelector('a.forumDisplayImgList') ??
        li.querySelector('a[href*="mod=viewthread"]') ??
        li.querySelector('a[href*="goto=findpost"]') ??
        li.querySelector('a[href*="ptid="]');
    if (a == null) continue;
    final href = attr(a, 'href');
    final tid = paramInt(href, 'tid') ?? paramInt(href, 'ptid');
    if (tid == null) continue;

    final count = li.querySelector('.count');
    final subj = li.querySelector('.threadSubject');
    final typeEl = subj?.querySelector('.threadType');
    final avatar = absolute(attr(li.querySelector('.h_avatar img'), 'src'));
    final digest = txt(li.querySelector('.xinruiInfo'));

    out.add(ThreadItem(
      tid: tid,
      title: txt(subj).replaceAll(txt(typeEl), '').trim(),
      type: txt(typeEl),
      author: txt(li.querySelector('h4')).replaceAll(txt(count), '').trim(),
      uid: paramInt(avatar, 'uid'),
      avatar: avatar,
      date: txt(li.querySelector('.threadListTit p')).replaceFirst(RegExp(r'^发布于\s*'), ''),
      views: digits(txt(li.querySelector('.views'))),
      replies: digits(txt(li.querySelector('.replies'))),
      digest: digest.length > 120 ? digest.substring(0, 120) : digest,
    ));
  }
  return out;
}

/* ─────────────── 帖子內頁 ─────────────── */

Future<ThreadData> fetchThread(int tid, {int page = 1}) async {
  final q = <String, String>{'mod': 'viewthread', 'tid': '$tid'};
  if (page > 1) q['page'] = '$page';
  return parseThread(await _page('forum.php?${_qs(q)}'), tid);
}

ThreadData parseThread(dom.Document doc, int tid) {
  final head = doc.querySelector('.postlist .forumListHeader');
  final attrBox = head?.querySelector('.postUserAttr');
  final authorLink = attrBox?.querySelector('a');
  final headAvatar = absolute(attr(attrBox?.querySelector('.h_avatar img'), 'src'));
  final backHref = attr(doc.querySelector('header .goBack'), 'href');
  final headTitle = txt(head?.querySelector('h2'));

  final items = doc.querySelectorAll('.postListItem');
  final posts = <PostItem>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final tit = it.querySelector('.postListTit');
    final link = tit?.querySelector('h4 a');
    final con = it.querySelector('.postListCon');
    final body = con?.querySelector('.postmessage') ?? con;
    // 附件圖放在 .postListCon 之外的 ul.img_list，只取內文會整批漏掉
    final withAttachments = _mergeAttachments(body, it);
    final av = absolute(attr(tit?.querySelector('.h_avatar img'), 'src'));
    final avatar = av.isNotEmpty ? av : headAvatar;
    final time = txt(it.querySelector('.postListAttr'));
    final spans = attrBox?.querySelectorAll('span') ?? const <dom.Element>[];

    posts.add(PostItem(
      pid: int.tryParse(attr(it, 'id').replaceFirst('pid', '')),
      floor: txt(tit?.querySelector('em')).isNotEmpty
          ? txt(tit?.querySelector('em'))
          : (i == 0 ? '樓主' : ''),
      author: link != null ? txt(link) : txt(authorLink),
      uid: paramInt(link != null ? attr(link, 'href') : avatar, 'uid'),
      avatar: avatar,
      time: time.isNotEmpty ? time : (spans.length > 1 ? txt(spans[1]) : ''),
      html: sanitizeContent(withAttachments),
      signature: sanitizeContent(it.querySelector('.sign')),
      quoteHref: attr(it.querySelector('.replybtn input'), 'href'),
      comments: _parseFloorComments(it),
    ));
  }

  return ThreadData(
    tid: tid,
    fid: paramInt(backHref, 'fid'),
    forumName: txt(doc.querySelector('header h1')),
    title: headTitle.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), ''),
    type: RegExp(r'^\[([^\]]*)\]').firstMatch(headTitle)?.group(1) ?? '',
    posts: posts,
    pager: parsePager(doc),
    poll: _parsePoll(doc),
    requiresLogin: isLoginWall(doc),
  );
}

/// 樓中樓（dxksst 外掛）：每個 li 的結構是
/// `<a href=...uid=X><em><img class=dxksst_avatar><font>暱稱</font></em></a><em>:內容</em>`
List<FloorComment> _parseFloorComments(dom.Element post) {
  final box = post.querySelector('.dxksst_floor');
  if (box == null) return const [];

  final out = <FloorComment>[];
  for (final li in box.querySelectorAll('li')) {
    final link = li.querySelector('a');
    final name = txt(li.querySelector('font'));
    // 結構是 <a><em>暱稱</em></a><em>:內容</em><div>時間</div>
    // 內容是 li 的「直接子 em」；用 querySelectorAll 取最後一個會抓到時間
    final direct = li.children.where((e) => e.localName == 'em').toList();
    final body = direct.isEmpty ? '' : txt(direct.first);
    final text = body.replaceFirst(RegExp(r'^[:：]\s*'), '');
    if (name.isEmpty && text.isEmpty) continue;
    out.add(FloorComment(
      uid: paramInt(attr(link, 'href'), 'uid'),
      name: name,
      avatar: attr(li.querySelector('.dxksst_avatar'), 'src'),
      text: text,
    ));
  }
  return out;
}

Poll? _parsePoll(dom.Document doc) {
  final box = doc.querySelector('.pollBox');
  if (box == null) return null;

  final form = box.querySelector('#poll') ?? box.querySelector('form');
  final options = <PollOption>[];
  var multiple = false;
  for (final input in box.querySelectorAll('input[name="pollanswers[]"]')) {
    if (attr(input, 'type') == 'checkbox') multiple = true;
    final label = input.parent;
    options.add(PollOption(
      attr(input, 'value'),
      txt(label).replaceFirst(RegExp(r'^\d+[.、]\s*'), ''),
    ));
  }

  // 已經投過票的話論壇不給 radio，改成每個選項附一條百分比長條
  if (options.isEmpty) {
    for (final label in box.querySelectorAll('label')) {
      final count = label.querySelector('.voteCount');
      if (count == null) continue;
      final em = txt(count.querySelector('em'));
      final text = txt(label)
          .replaceFirst(em, '')
          .replaceFirst(RegExp(r'^\d+[.、]\s*'), '')
          .trim();
      if (text.isEmpty) continue;
      options.add(PollOption(
        '',
        text,
        percent: RegExp(r'[\d.]+%').firstMatch(em)?.group(0) ?? '',
        votes: int.tryParse(txt(count.querySelector('strong'))
                .replaceAll(RegExp(r'\D'), '')) ??
            0,
      ));
    }
  }

  return Poll(
    title: txt(box.querySelector('.pollTit h3')),
    info: txt(box.querySelector('.pollUser')),
    deadline: txt(box.querySelector('.pollTime')),
    // 「您已经投过票，谢谢您的参与」就在這顆灰按鈕裡
    status: txt(box.querySelector('.btn_pn_grey')),
    options: options,
    multiple: multiple,
    formhash: attr(box.querySelector('input[name="formhash"]'), 'value'),
    action: attr(form, 'action'),
  );
}

Future<SubmitResult> votePoll(Poll poll, List<String> answers) async {
  if (poll.action.isEmpty || answers.isEmpty) {
    return const SubmitResult(ok: false, message: '請先選擇選項');
  }
  final body = StringBuffer('formhash=${Uri.encodeQueryComponent(poll.formhash)}');
  for (final a in answers) {
    body.write('&pollanswers%5B%5D=${Uri.encodeQueryComponent(a)}');
  }
  final html = await Api.instance.postRaw(
      poll.action.replaceAll('&amp;', '&'), body.toString());
  return _submitResult(html, '投票');
}


/// 把內文和附件圖清單合成一個節點再淨化。
///
/// Discuz 手機版把附件圖放在 `<ul class="img_list">`，那是 .postListCon 的
/// 兄弟節點而不是內文的一部分 —— 只讀內文的話用附件上傳的照片全都不會出現。
dom.Element? _mergeAttachments(dom.Element? body, dom.Element post) {
  // .img_list 是附件圖；訪客或權限不足時論壇會改放 .warning 提示
  //（「您需要登录才可以下载或查看附件」），兩者都在內文之外
  final lists = [
    ...post.querySelectorAll('.img_list'),
    ...post.querySelectorAll('.warning'),
  ];
  if (lists.isEmpty) return body;

  final wrap = dom.Element.tag('div');
  if (body != null) {
    for (final n in body.nodes.toList()) {
      wrap.append(n.clone(true));
    }
  }
  for (final ul in lists) {
    final copy = ul.clone(true);
    // 附件圖外面包著連到附件頁的 <a>，拆掉才不會蓋掉點圖放大的手勢
    for (final a in copy.querySelectorAll('a').toList()) {
      if (a.querySelector('img') == null) continue;
      for (final child in a.nodes.toList()) {
        a.parent?.insertBefore(child.clone(true), a);
      }
      a.remove();
    }
    wrap.append(copy);
  }
  return wrap;
}

/* ─────────────── 導讀 / 搜尋 ─────────────── */

Future<ListPage> fetchGuide({String view = 'newthread', int page = 1}) async {
  final q = <String, String>{'mod': 'guide', 'view': view};
  if (page > 1) q['page'] = '$page';
  final doc = await _page('forum.php?${_qs(q)}');
  return ListPage(
      list: parseThreadList(doc), pager: parsePager(doc, current: page));
}

Future<ListPage> search(String keyword, {int page = 1}) async {
  final q = <String, String>{
    'mod': 'forum',
    'srchtxt': keyword,
    'formhash': _formhash ?? '',
    'searchsubmit': 'yes',
    'source': 'hotsearch',
  };
  if (page > 1) q['page'] = '$page';
  final doc = await _page('search.php?${_qs(q)}');

  final list = parseThreadList(doc);
  if (list.isNotEmpty) {
    return ListPage(list: list, pager: parsePager(doc, current: page));
  }

  // 搜尋結果頁版型和主題列表不同時，退而抓所有 viewthread 連結
  final seen = <int, ThreadItem>{};
  for (final a in doc.querySelectorAll('a[href*="mod=viewthread"]')) {
    final tid = paramInt(attr(a, 'href'), 'tid');
    final title = txt(a);
    if (tid != null && title.isNotEmpty) {
      seen.putIfAbsent(tid, () => ThreadItem(tid: tid, title: title));
    }
  }
  return ListPage(
    list: seen.values.toList(),
    pager: parsePager(doc, current: page),
    message: noticeMessage(doc),
  );
}

/* ─────────────── 發文 / 回覆 ─────────────── */

/// Discuz 發文成功時會 302 轉到帖子頁，dio 跟隨轉址後拿到的是帖子內容，
/// 裡面不會有任何「成功」字樣 —— 靠正面關鍵字判斷會把成功誤判成失敗。
///
/// 而且 `.alert_error` 也不能當失敗依據：連「欢迎您回来」這種成功訊息
/// Discuz 都包在 alert_error 裡。
///
/// 所以改成：落在帖子頁＝成功；否則看訊息文字比對已知的失敗樣態。
final _failurePatterns = RegExp(
    '权限|權限|间隔|間隔|太快|过快|禁止|不能|无权|無權|失败|失敗|错误|錯誤|'
    '请先登录|請先登錄|需要先登录|需要先登入|尚未登录|尚未登入|'
    '抱歉|不存在|已关闭|已關閉');

SubmitResult submitResult(String html, String what) => _submitResult(html, what);

SubmitResult _submitResult(String html, String what) {
  // 明確的錯誤呼叫 errorhandle_x('訊息', {})。注意論壇連「操作成功」也走
  // errorhandle_（例如刪提醒），所以成敗還是要看訊息本身，不能一律當失敗。
  final err = RegExp(r"errorhandle_\w*\('([^']*)'").firstMatch(html)?.group(1);
  if (err != null && err.trim().isNotEmpty) {
    final raw = err.trim();
    return SubmitResult(ok: !_failurePatterns.hasMatch(raw), message: sys(raw));
  }

  // ajax 回應常常整包只是一段 <script>，直接把 body 當訊息會連 JavaScript
  // 一起唸出來。訊息可能在 showDialog('…') 或 succeedhandle_x(url, '…', {…})
  final dialog = RegExp(r"showDialog\('([^']*)'").firstMatch(html)?.group(1) ??
      RegExp(r"succeedhandle_\w+\('[^']*',\s*'([^']*)'")
          .firstMatch(html)
          ?.group(1);
  if (dialog != null && dialog.trim().isNotEmpty) {
    final raw = dialog.trim();
    // 成敗要看原文 —— 轉成繁體之後「需要先登录」就對不上樣式了
    return SubmitResult(ok: !_failurePatterns.hasMatch(raw), message: sys(raw));
  }

  final doc = toDoc(html);

  // 論壇把我們轉到登入頁 = 這個操作根本沒送出。
  // 少了這一關，訪客按回覆／收藏／評分都會顯示「成功」但實際什麼都沒發生。
  if (isLoginWall(doc)) {
    return SubmitResult(ok: false, message: '需要先登入才能$what');
  }
  final notice = noticeMessage(doc) ?? '';
  if (RegExp('需要先登录|需要先登入|请先登录|請先登入|尚未登录|尚未登入').hasMatch(notice) ||
      RegExp('您需要先登录才能继续本操作').hasMatch(html)) {
    return SubmitResult(ok: false, message: '需要先登入才能$what');
  }

  // 轉址後落在帖子頁 → 一定是成功（手機版 .postListItem／桌面版 #postlist）
  if (doc.querySelector('.postListItem') != null ||
      doc.querySelector('.postlist') != null ||
      doc.getElementById('postlist') != null) {
    return SubmitResult(ok: true, message: '$what成功');
  }

  final msg = noticeMessage(doc);
  if (msg != null && _failurePatterns.hasMatch(msg)) {
    return SubmitResult(ok: false, message: msg);
  }

  final jump = attr(doc.querySelector('.jump_c a'), 'href');
  if (jump.contains('mod=viewthread') ||
      jump.contains('mod=redirect') ||
      jump.contains('goto=findpost')) {
    return SubmitResult(ok: true, message: msg ?? '$what成功');
  }

  if (RegExp('succeed|非常感谢|发布成功|操作成功|成功').hasMatch(html)) {
    return SubmitResult(ok: true, message: msg ?? '$what成功');
  }

  // 沒有明確的失敗跡象就不要嚇使用者 —— 之前正是這裡把成功報成失敗
  return SubmitResult(ok: true, message: msg ?? '$what已送出');
}

Future<SubmitResult> replyThread({
  required int fid,
  required int tid,
  required String message,
  String repquote = '',
  int page = 1,
}) async {
  var url = 'forum.php?mod=post&action=reply&fid=$fid&tid=$tid';
  if (repquote.isNotEmpty) url += '&repquote=$repquote';

  final form = await Api.instance.get(url);
  final doc = toDoc(form);
  final hash = _capture(doc, form) ?? '';
  final posttime = attr(doc.querySelector('input[name="posttime"]'), 'value');

  final html = await Api.instance.post(
    'forum.php?mod=post&action=reply&fid=$fid&tid=$tid&extra=&replysubmit=yes&page=$page',
    {
      'formhash': hash,
      'posttime': posttime.isNotEmpty
          ? posttime
          : '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'message': message,
      'special': '1',
      'replysubmit': 'yes',
      'usesig': '1',
      'subject': '',
    },
    desktop: true,
  );
  return _submitResult(html, '回覆');
}

Future<SubmitResult> newThread({
  required int fid,
  required String subject,
  required String message,
  String typeid = '',
}) async {
  final form = await Api.instance.get('forum.php?mod=post&action=newthread&fid=$fid');
  final doc = toDoc(form);
  final hash = _capture(doc, form) ?? '';
  final posttime = attr(doc.querySelector('input[name="posttime"]'), 'value');

  final html = await Api.instance.post(
    'forum.php?mod=post&action=newthread&fid=$fid&extra=&topicsubmit=yes',
    {
      'formhash': hash,
      'posttime': posttime.isNotEmpty
          ? posttime
          : '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'subject': subject,
      'message': message,
      'typeid': typeid,
      'topicsubmit': 'yes',
      'usesig': '1',
      'allownoticeauthor': '1',
    },
    desktop: true,
  );
  return _submitResult(html, '發表');
}

/// 讀取發文頁可選的主題分類（很多版塊強制要選）
Future<NewThreadMeta> newThreadMeta(int fid) async {
  final doc = await _page('forum.php?mod=post&action=newthread&fid=$fid');
  final sel = doc.querySelector('select[name="typeid"]');
  return NewThreadMeta(
    types: (sel?.querySelectorAll('option') ?? const <dom.Element>[])
        .map((o) => ThreadType(typeid: int.tryParse(attr(o, 'value')) ?? 0, name: txt(o)))
        .where((t) => t.typeid > 0)
        .toList(),
    canPost: doc.querySelector('textarea[name="message"]') != null,
    message: noticeMessage(doc),
  );
}

/* ─────────────── 簽到（k_misign 外掛） ─────────────── */

Future<SubmitResult> doSign() async {
  await _ensureFormhash();
  final html = await Api.instance
      .get('plugin.php?id=k_misign:sign&operation=qiandao&format=text&formhash=$_formhash');
  final doc = toDoc(html);
  final text = txt(doc.body).isNotEmpty
      ? txt(doc.body)
      : html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  // 未登入時論壇回一整頁提示，直接丟給使用者會是一大段亂七八糟的文字
  if (RegExp('需要先登录|需要先登入|请先登录|請先登入').hasMatch(text)) {
    return const SubmitResult(ok: false, message: '需要先登入才能簽到');
  }
  return SubmitResult(
    ok: RegExp('已签到|成功|签到').hasMatch(text),
    message: text.isEmpty ? '簽到完成' : text,
  );
}

Future<SignResult> fetchSignPage() async {
  final doc = await _page('plugin.php?id=k_misign:sign');

  // 簽到外掛的資料是結構化的，直接把整頁 HTML 倒出來會連頁尾、
  // 側邊導覽一起畫進去，所以拆成欄位自己排版
  final stats = <({String label, String value})>[];
  for (final item in doc.querySelectorAll('.info .item')) {
    final rows = item.children.where((e) => e.localName == 'div').toList();
    if (rows.length < 2) continue;
    final label = txt(rows[0]);
    final value = txt(rows[1]);
    if (label.isNotEmpty && value.isNotEmpty) {
      stats.add((label: sys(label), value: sys(value)));
    }
  }

  final header = txt(doc.querySelector('.k_misign_header'));
  final level = RegExp(r'[签簽]到等[级級]\s*Lv\s*\d+').firstMatch(header)?.group(0) ?? '';

  return SignResult(
    html: stats.isEmpty
        ? sanitizeContent(doc.querySelector('.k_misign_header') ??
            doc.querySelector('.container'))
        : '',
    signed: doc.querySelector('.btn_visited') != null ||
        RegExp('已签到|已簽到').hasMatch(header),
    level: sys(level),
    stats: stats,
  );
}

/// 簽到的說明頁（獎勵規則／簽到等級／道具擴展）。只有桌面模板
Future<SignRules> fetchSignRules(String op) async {
  final doc =
      toDoc(await Api.instance.get('k_misign-misc.html?operation=$op', desktop: true));
  final main = doc.querySelector('.mn') ?? doc.body!;

  final tables = <SignRuleTable>[];
  for (final table in main.querySelectorAll('table')) {
    // 表格前面那個 bm_h 是它的標題
    var title = '';
    for (var n = table.parent; n != null; n = n.parent) {
      final head = n.previousElementSibling;
      if (head != null && head.classes.contains('bm_h')) {
        title = txt(head);
        break;
      }
    }

    final rows = <List<String>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cells = <String>[];
      for (final td in tr.querySelectorAll('td')) {
        // 論壇每列開頭都塞一個空的圖示欄
        if (td.classes.contains('icn')) continue;
        cells.add(sys(txt(td)));
      }
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    if (rows.isNotEmpty) {
      tables.add(SignRuleTable(title: sys(title), rows: rows));
    }
  }

  return SignRules(
    intro: sys(txt(main.querySelector('.bm_c p'))),
    tables: tables,
    text: tables.isEmpty ? sys(txt(main)) : '',
  );
}

/// 我訂閱的專輯（淘帖）。只有桌面模板
Future<List<CollectionItem>> fetchCollections() async {
  final doc = toDoc(
      await Api.instance.get('forum.php?mod=collection&op=my', desktop: true));
  final out = <CollectionItem>[];

  for (final dl in doc.querySelectorAll('.clct_list dl')) {
    final a = dl.querySelector('dt a[href*="ctid="]');
    final ctid = paramInt(attr(a, 'href'), 'ctid');
    if (a == null || ctid == null) continue;

    final ps = dl.querySelectorAll('dd p');
    final latest = dl.querySelector('a[href*="thread-"]');

    out.add(CollectionItem(
      ctid: ctid,
      name: txt(a),
      threads: txt(dl.querySelector('dd.m strong')),
      desc: ps.isNotEmpty ? txt(ps[0]) : '',
      meta: ps.length > 1 ? txt(ps[1]) : '',
      author: txt(dl.querySelector('a[href*="space-uid"]')),
      latest: txt(latest),
      latestTid: int.tryParse(
          RegExp(r'thread-(\d+)').firstMatch(attr(latest, 'href'))?.group(1) ??
              ''),
    ));
  }
  return out;
}

/// 淘帖列表：推薦／所有／我的。op 空字串是推薦
Future<({List<CollectionItem> items, PageInfo pager})> fetchCollectionIndex({
  String op = '',
  int page = 1,
}) async {
  final q = StringBuffer('forum.php?mod=collection');
  if (op.isNotEmpty) q.write('&op=$op');
  if (page > 1) q.write('&page=$page');
  return parseCollectionIndex(
      toDoc(await Api.instance.get(q.toString(), desktop: true)),
      page: page);
}

({List<CollectionItem> items, PageInfo pager}) parseCollectionIndex(
    dom.Document doc,
    {int page = 1}) {
  final out = <CollectionItem>[];
  for (final dl in doc.querySelectorAll('.clct_list dl')) {
    final a = dl.querySelector('dt a[href*="ctid="]');
    final ctid = paramInt(attr(a, 'href'), 'ctid');
    if (a == null || ctid == null) continue;
    final ps = dl.querySelectorAll('dd p');
    final latest = dl.querySelector('a[href*="thread-"]');
    final creator = dl.querySelector('a[href*="space-uid"]');
    // 標籤：ctag_keyword 裡的搜尋連結
    final tags = <CollectionTag>[];
    for (final t in dl.querySelectorAll('.ctag_keyword a')) {
      final name = txt(t);
      final kw = param(attr(t, 'href'), 'srchtxt') ?? name;
      if (name.isNotEmpty) tags.add(CollectionTag(name, kw));
    }
    out.add(CollectionItem(
      ctid: ctid,
      name: txt(a),
      threads: txt(dl.querySelector('dd.m strong')),
      desc: ps.isNotEmpty ? txt(ps[0]) : '',
      meta: ps.length > 1 ? txt(ps[1]) : '',
      author: txt(creator),
      authorUid: paramInt(attr(creator, 'href'), 'uid') ??
          int.tryParse(
              RegExp(r'space-uid-(\d+)').firstMatch(attr(creator, 'href'))?.group(1) ?? ''),
      tags: tags,
      latest: txt(latest),
      latestTid: int.tryParse(
          RegExp(r'thread-(\d+)').firstMatch(attr(latest, 'href'))?.group(1) ??
              ''),
    ));
  }
  return (items: out, pager: parsePager(doc, current: page));
}

int _starCount(dom.Element? el) {
  final cls = el?.querySelector('.star')?.className ?? '';
  return int.tryParse(RegExp(r'star(\d)').firstMatch(cls)?.group(1) ?? '0') ?? 0;
}

/// 淘專輯內頁：專輯資訊 + 收錄的主題清單
Future<CollectionView> fetchCollectionThreads(int ctid, {int page = 1}) async {
  final doc = toDoc(await Api.instance.get(
      'forum.php?mod=collection&action=view&ctid=$ctid'
      '${page > 1 ? '&page=$page' : ''}',
      desktop: true));
  return parseCollectionView(doc, ctid, page: page);
}

CollectionView parseCollectionView(dom.Document doc, int ctid, {int page = 1}) {
  final head = doc.querySelector('.bm_h h2 a') ?? doc.querySelector('.bm_h h2');
  final follow = doc.querySelector('#followlink');

  final list = <ThreadItem>[];
  for (final tr in doc.querySelectorAll('.tl .bm_c table tr')) {
    final a = tr.querySelector('th a.xst') ?? tr.querySelector('th a');
    final tid = paramInt(attr(a, 'href'), 'tid') ??
        int.tryParse(RegExp(r'thread-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? '');
    if (a == null || tid == null) continue;
    final bys = tr.querySelectorAll('td.by');
    final num = tr.querySelector('td.num');
    list.add(ThreadItem(
      tid: tid,
      title: txt(a),
      author: bys.isNotEmpty ? txt(bys[0].querySelector('cite')) : '',
      date: bys.isNotEmpty ? txt(bys[0].querySelector('em')) : '',
      replies: int.tryParse(txt(num?.querySelector('a'))) ?? 0,
      views: int.tryParse(txt(num?.querySelector('em'))) ?? 0,
    ));
  }

  // 我自己建的才有編輯／刪除／邀請維護
  final edit = doc.querySelector('a[href*="op=edit"]');
  final remove = doc.querySelector('a[href*="op=remove"]');
  final invite = doc.querySelector('#k_invite');
  final creator = doc.querySelector('.mbn a[href*="space-uid"]') ??
      doc.querySelector('.bm_c a[href*="space-uid"]');

  // 最新评论：一組是 .pbn（作者＋日期）＋ .pbm（星數＋文字）
  final comments = <CollectionComment>[];
  final commentBlock = doc.querySelectorAll('.bm').where((b) =>
      txt(b.querySelector('h2')).contains('评论') ||
      txt(b.querySelector('h2')).contains('評論'));
  for (final b in commentBlock) {
    final heads = b.querySelectorAll('.bm_c .pbn');
    final bodies = b.querySelectorAll('.bm_c .pbm');
    for (var i = 0; i < heads.length; i++) {
      final who = heads[i].querySelector('a[href*="space-uid"]');
      if (who == null) continue;
      final body = i < bodies.length ? bodies[i] : null;
      comments.add(CollectionComment(
        author: txt(who),
        uid: paramInt(attr(who, 'href'), 'uid') ??
            int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(attr(who, 'href'))?.group(1) ?? ''),
        date: txt(heads[i].querySelector('.xg1')).replaceAll(RegExp(r'[:：]\s*$'), ''),
        stars: _starCount(body),
        text: body == null
            ? ''
            : txt(body).replaceAll(RegExp(r'^\d+\s*'), ''),
      ));
    }
    break;
  }

  final ratingEl = doc.querySelector('.ptn.pbn.xg1');

  return CollectionView(
    ctid: ctid,
    name: txt(head),
    desc: txt(doc.querySelector('.bm_c .mbn')?.nextElementSibling ??
        doc.querySelector('.bm_c > div:last-child')),
    author: txt(creator),
    authorUid: paramInt(attr(creator, 'href'), 'uid') ??
        int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(attr(creator, 'href'))?.group(1) ?? ''),
    rating: txt(ratingEl),
    follows: txt(doc.getElementById('follownum_display')),
    followUrl: '',
    following: txt(follow).contains('取消'),
    mine: edit != null && remove != null,
    editUrl: absolute(attr(edit, 'href')),
    removeUrl: absolute(attr(remove, 'href')),
    inviteUrl: absolute(attr(invite, 'href')),
    recommendUrl: absolute(attr(doc.querySelector('#k_recommened'), 'href')),
    formhash: formhashOf(doc) ?? _formhash ?? '',
    comments: comments,
    list: list,
    pager: parsePager(doc, current: page),
    message: list.isEmpty ? (noticeMessage(doc) ?? '這個專輯還沒有主題') : null,
  );
}

/// 向作者推薦主題
Future<SubmitResult> recommendThreadToCollection(int ctid, String threadUrl,
    {String formhash = ''}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post(
    'forum.php?mod=collection&action=comment&op=recommend&ctid=$ctid&inajax=1',
    {'threadurl': threadUrl, 'formhash': hash},
    desktop: true,
  );
  return _submitResult(html, '推薦主題');
}

/// 發表評論（可附評分 1~5）
Future<SubmitResult> commentCollection(int ctid, String message,
    {int score = 0, String formhash = ''}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post(
    'forum.php?mod=collection&action=comment&ctid=$ctid&inajax=1',
    {
      'message': message,
      if (score > 0) 'ratescore': '$score',
      'formhash': hash,
      'handlekey': 'k_addComment',
    },
    desktop: true,
  );
  return _submitResult(html, '評論');
}

/// 編輯淘專輯（名稱／簡介／標籤）
Future<SubmitResult> editCollection(int ctid,
    {required String title, String desc = '', String keyword = '', String formhash = ''}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post('forum.php?mod=collection&action=edit&inajax=1', {
    'title': title,
    'desc': desc,
    'keyword': keyword,
    'submitcollection': '1',
    'op': 'edit',
    'ctid': '$ctid',
    'formhash': hash,
  }, desktop: true);
  return _submitResult(html, '編輯');
}

/// 刪除淘專輯。論壇是一步 GET（確認後 window.location = 這個網址）
Future<SubmitResult> removeCollection(int ctid, {String formhash = ''}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.get(
      'forum.php?mod=collection&action=edit&op=remove&ctid=$ctid&formhash=$hash&inajax=1',
      desktop: true);
  return _submitResult(html, '刪除');
}

/// 訂閱／取消訂閱某個淘專輯
Future<SubmitResult> followCollection(int ctid, {required bool follow}) async {
  await _ensureFormhash();
  // 論壇的 op 是 follow / unfo（不是 unfollow）
  final op = follow ? 'follow' : 'unfo';
  final html = await Api.instance.get(
      'forum.php?mod=collection&action=follow&op=$op&ctid=$ctid'
      '&formhash=$_formhash&inajax=1',
      desktop: true);
  return _submitResult(html, follow ? '訂閱' : '取消訂閱');
}

/// 淘帖：把主題加進哪個專輯。先抓表單拿到我的專輯清單與 formhash
Future<({List<({int ctid, String name})> collections, String formhash})>
    fetchAddThreadCollections(int tid) async {
  final xml = await Api.instance.get(
      'forum.php?mod=collection&action=edit&op=addthread&tid=$tid&inajax=1',
      desktop: true);
  final doc = toDoc(_unwrapAjax(xml));
  final out = <({int ctid, String name})>[];
  for (final o in doc.querySelectorAll('#selectCollection option')) {
    final ctid = int.tryParse(attr(o, 'value'));
    if (ctid == null) continue;
    out.add((ctid: ctid, name: txt(o)));
  }
  return (collections: out, formhash: formhashOf(doc) ?? _formhash ?? '');
}

/// 把主題加進指定的淘專輯
Future<SubmitResult> addThreadToCollection(
  int tid,
  int ctid, {
  String reason = '',
  String formhash = '',
}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post(
    'forum.php?mod=collection&action=edit&op=addthread&inajax=1',
    {
      'formhash': hash,
      'ctid': '$ctid',
      'tids[]': '$tid',
      'reason': reason,
      'addthread': '1',
      'submitaddthread': 'true',
    },
    desktop: true,
  );
  return _submitResult(html, '淘帖');
}

/// 頂／踩一個主題（推薦）
Future<SubmitResult> recommendThread(int tid, {required bool up}) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'forum.php?mod=misc&action=recommend&do=${up ? 'add' : 'subtract'}'
      '&tid=$tid&hash=$_formhash&inajax=1');
  final text = txt(toDoc(_unwrapAjax(html)).body);
  return SubmitResult(
      ok: !_failurePatterns.hasMatch(text),
      message: sys(text.isEmpty ? (up ? '已頂' : '已踩') : text));
}

/// 舉報一則帖子
Future<SubmitResult> reportPost({
  required int pid,
  required int tid,
  required int fid,
  required String reason,
}) async {
  await _ensureFormhash();
  final html = await Api.instance.post('misc.php?mod=report&inajax=1', {
    'formhash': _formhash ?? '',
    'rtype': 'post',
    'rid': '$pid',
    'tid': '$tid',
    'fid': '$fid',
    'message': reason,
    'reportsubmit': 'true',
  });
  return _submitResult(html, '舉報');
}

/// 用論壇給的完整收藏連結收藏（群組那種 `#a_favorite` 的 href）。一步 GET。
Future<SubmitResult> favoriteByUrl(String url) async {
  var path = url.replaceAll('&amp;', '&');
  // 兩種前綴都要認：網頁版的 kOrigin 是自家轉發位址，但頁面裡的連結
  // 用的是論壇本尊的網址
  if (path.startsWith(kOrigin)) {
    path = path.substring(kOrigin.length);
  } else if (path.startsWith(kForumOrigin)) {
    path = path.substring(kForumOrigin.length);
  }
  path = path.replaceFirst(RegExp(r'^/'), '');
  final sep = path.contains('?') ? '&' : '?';
  final html = await Api.instance.get('$path${sep}inajax=1', desktop: true);
  return _submitResult(html, '收藏');
}

/// 收藏版塊。跟收藏主題一樣是一步 GET，不是刪除那種兩步驟。
/// （論壇的「收藏本版」連結一律指向新增，已收藏時會回「请勿重复收藏」，
///   所以要不要顯示成已收藏，得靠收藏清單判斷。）
Future<SubmitResult> favoriteForum(int fid) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=favorite&type=forum&id=$fid'
      '&handlekey=favoriteforum&formhash=$_formhash&inajax=1',
      desktop: true);
  return _submitResult(html, '收藏本版');
}
Future<ForumExtras> fetchForumExtras(int fid) async {
  final doc =
      toDoc(await Api.instance.get('forum-$fid-1.html', desktop: true));

  final rules = doc.getElementById('forum_rules_$fid');
  final fav = doc.querySelector('#a_favorite');

  // 版主只在版規那塊上面那一行，整頁掃會把主題列表的作者也撈進來
  final mods = <ProfileLink>[];
  for (final div in doc.querySelectorAll('.bm_c div')) {
    if (!txt(div).startsWith('版主')) continue;
    for (final a in div.querySelectorAll('a[href*="space-username"]')) {
      final name = txt(a);
      if (name.isEmpty || mods.any((m) => m.name == name)) continue;
      mods.add(ProfileLink(name, url: absolute(attr(a, 'href'))));
    }
    break;
  }

  return ForumExtras(
    rulesHtml: rules == null ? '' : sanitizeContent(rules),
    moderators: mods,
    favoriteUrl: absolute(attr(fav, 'href')),
    favoriteCount: txt(doc.getElementById('number_favorite_num')),
  );
}

/// 收藏清單。論壇左側那排分類（帖子／版塊／群組／日誌／相冊）共用這一支
Future<({List<FavoriteItem> items, PageInfo pager})> fetchFavoriteList(
  int uid, {
  String type = 'all',
  int page = 1,
}) async {
  final q = 'home.php?mod=space&uid=$uid&do=favorite&view=me&type=$type'
      '${page > 1 ? '&page=$page' : ''}';
  final doc = toDoc(await Api.instance.get(q, desktop: true));

  final items = <FavoriteItem>[];
  for (final li in doc.querySelectorAll('#favorite_ul li')) {
    final favid = paramInt(
        attr(li.querySelector('a[href*="op=delete"]'), 'href'), 'favid');
    // 標題是那個 target=_blank 的連結，刪除連結不是
    final a = li.querySelector('a[target="_blank"]');
    if (favid == null || a == null) continue;

    final href = attr(a, 'href');
    final kind = _favKindOf(href, attr(li.querySelector('span img'), 'alt'));
    items.add(FavoriteItem(
      favid: favid,
      title: txt(a),
      type: kind,
      url: absolute(href),
      date: txt(li.querySelector('span.xg1')),
      targetId: int.tryParse(
              RegExp(r'(?:thread|forum|group|blog)-(\d+)')
                      .firstMatch(href)
                      ?.group(1) ??
                  '') ??
          paramInt(href, 'tid') ??
          paramInt(href, 'fid') ??
          paramInt(href, 'id'),
    ));
  }

  return (items: items, pager: parsePager(doc, current: page));
}

String _favKindOf(String href, String alt) {
  if (href.contains('thread-') || href.contains('mod=viewthread')) return 'thread';
  if (href.contains('group-')) return 'group';
  if (href.contains('forum-') || href.contains('forumdisplay')) return 'forum';
  if (href.contains('blog-')) return 'blog';
  if (href.contains('do=album')) return 'album';
  return alt;
}

/// 簽到的道具擴展（補簽卡）。可以直接補簽或購買，不是單純一段說明
Future<List<SignMagic>> fetchSignMagics() async {
  final doc = toDoc(await Api.instance
      .get('k_misign-misc.html?operation=magics', desktop: true));
  final out = <SignMagic>[];

  for (final dl in doc.querySelectorAll('.xld')) {
    final name = txt(dl.querySelector('dt'));
    if (name.isEmpty) continue;
    final ps = dl.querySelectorAll('dd p');
    out.add(SignMagic(
      name: sys(name),
      icon: absolute(attr(dl.querySelector('dd.m img'), 'src')),
      desc: ps.isNotEmpty ? sys(txt(ps[0])) : '',
      detail: ps.length > 1 ? sys(txt(ps[1])) : '',
      useUrl: absolute(attr(dl.querySelector('a[id\$="_bq"]'), 'href')),
      buyUrl: absolute(attr(dl.querySelector('a[id\$="_buy"]'), 'href')),
    ));
  }
  return out;
}

/// 道具彈窗（補簽卡的補簽／購買、帖子的提升泵／亮色刷…）。
/// 論壇對「買」跟「用」都回同一種 magicform，把整張表單收下來，
/// 送出時原封帶回。沒有表單就代表論壇直接回了錯誤（沒有道具、缺貨）。
Future<MagicOp> fetchMagicOp(String url) async {
  var path = url.replaceAll('&amp;', '&');
  if (path.startsWith(kOrigin)) path = path.substring(kOrigin.length);
  path = path.replaceFirst(RegExp(r'^/'), '');
  final sep = path.contains('?') ? '&' : '?';
  final xml =
      await Api.instance.get('$path${sep}inajax=1', desktop: true);
  return parseMagicOp(toDoc(_unwrapAjax(xml)));
}

/// 從道具彈窗的 HTML 解析出 MagicOp（買／用共用一種 magicform）
MagicOp parseMagicOp(dom.Document doc) {
  final form = doc.querySelector('#magicform') ?? doc.querySelector('form');
  if (form == null) {
    // 沒表單＝論壇直接給了提示（例如「没有该道具」）
    final body = txt(doc.body);
    return MagicOp(
      action: '',
      operation: '',
      submitName: '',
      fields: const {},
      error: sys(noticeMessage(doc) ?? (body.isEmpty ? '拿不到道具資訊' : body)),
    );
  }

  final fields = <String, String>{};
  for (final input in form.querySelectorAll('input')) {
    final name = attr(input, 'name');
    if (name.isEmpty) continue;
    fields[name] = attr(input, 'value');
  }

  // 送出鈕的 name 才是論壇認的送出旗標
  var submitName = '';
  for (final b in form.querySelectorAll('button[type="submit"], input[type="submit"]')) {
    final n = attr(b, 'name');
    if (n.isNotEmpty) {
      submitName = n;
      break;
    }
  }
  final operation = fields['operation'] ?? '';
  if (submitName.isEmpty) {
    submitName = operation == 'use' ? 'usesubmit' : 'operatesubmit';
  }

  // 標題：dt 裡第一個 <p>，退而求其次用 dt 的文字
  final dt = form.querySelector('dt');
  final titleP = dt?.querySelector('p');
  final name = sys(txt(titleP).isNotEmpty ? txt(titleP) : txt(dt));

  // 說明各行（售價／我目前有／庫存／本月還能用…），跳過標題那行
  final lines = <String>[];
  for (final p in dt?.querySelectorAll('p') ?? const <dom.Element>[]) {
    final t = sys(txt(p));
    if (t.isEmpty || t == name) continue;
    lines.add(t);
  }

  return MagicOp(
    action: attr(form, 'action').replaceAll('&amp;', '&'),
    operation: operation,
    submitName: submitName,
    fields: fields,
    name: name,
    icon: absolute(attr(form.querySelector('dd img') ?? form.querySelector('img'), 'src')),
    lines: lines,
    hasNum: form.querySelector('#magicnum') != null,
    error: null,
  );
}

/// 送出道具操作。把彈窗裡的隱藏欄位原樣送回，補上數量與送出旗標。
Future<SubmitResult> submitMagicOp(MagicOp op, {int num = 1}) async {
  final fields = <String, String>{...op.fields};
  if (op.hasNum) fields['magicnum'] = '$num';
  fields[op.submitName] = 'true';

  var target = op.action.isEmpty
      ? 'home.php?mod=magic&action=shop&infloat=yes'
      : op.action;
  if (target.startsWith(kOrigin)) target = target.substring(kOrigin.length);
  target = target.replaceFirst(RegExp(r'^/'), '');

  final html = await Api.instance.post(
      '$target${target.contains('?') ? '&' : '?'}inajax=1', fields,
      desktop: true);
  return _submitResult(html, op.operation == 'use' ? '使用道具' : '購買道具');
}

/// 簽到排行榜。今日／本月／總／獎勵四種，op 空字串是今日
Future<List<SignRankRow>> fetchSignRank({String op = '', int page = 1}) async {
  final q = StringBuffer('plugin.php?id=k_misign:sign&operation=list');
  if (op.isNotEmpty) q.write('&op=$op');
  if (page > 1) q.write('&page=$page');
  return parseSignRank(
      toDoc(_unwrapAjax(await Api.instance.get(q.toString(), desktop: true))));
}

List<SignRankRow> parseSignRank(dom.Document doc) {
  final out = <SignRankRow>[];
  for (final tr in doc.querySelectorAll('#J_list_detail tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 6) continue; // 跳過表頭與分頁列
    final a = tds[0].querySelector('a');
    final name = txt(a);
    if (name.isEmpty) continue;
    out.add(SignRankRow(
      name: name,
      uid: paramInt(attr(a, 'href'), 'uid') ??
          int.tryParse(
              RegExp(r'space-uid-(\d+)').firstMatch(attr(a, 'href'))?.group(1) ?? ''),
      totalDays: txt(tds[1]),
      monthDays: txt(tds[2]),
      lastTime: txt(tds[3]),
      level: sys(txt(tds[4])),
      reward: sys(txt(tds[5])),
    ));
  }
  return out;
}

/// 附件的購買紀錄
Future<List<({String user, String date, String price})>> fetchAttachPayments(
    int aid) async {
  final doc = toDoc(await Api.instance.get(
      'forum.php?mod=misc&action=viewattachpayments&aid=$aid',
      desktop: true));

  // 欄位順序是 用户名 / 时间 / 金币；表頭用的是 <th>，自然不會混進來
  final out = <({String user, String date, String price})>[];
  for (final tr in doc.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 2) continue;
    final user = txt(tds[0]);
    if (user.isEmpty) continue;
    out.add((
      user: user,
      date: attr(tds[1].querySelector('span[title]'), 'title').isNotEmpty
          ? attr(tds[1].querySelector('span[title]'), 'title')
          : txt(tds[1]),
      price: tds.length > 2 ? sys(txt(tds[2])) : '',
    ));
  }
  return out;
}

/// 附件的原始位元組，存檔用
Future<Uint8List> fetchAttachmentBytes(String url) {
  var path = url.replaceAll('&amp;', '&');
  if (path.startsWith(kOrigin)) path = path.substring(kOrigin.length);
  return Api.instance.getBytes(path.replaceFirst(RegExp(r'^/'), ''));
}

/* ─────────────── 通知 / 私訊 ─────────────── */

/// 通知的兩層分類，取自論壇實際提供的連結
class NoticeTab {
  final String view;
  final String type;
  final String name;
  const NoticeTab(this.view, this.type, this.name);
}

const noticeViews = <NoticeTab>[
  NoticeTab('mypost', '', '我的帖子'),
  NoticeTab('interactive', '', '壇友互動'),
  NoticeTab('system', '', '系統提醒'),
  NoticeTab('app', '', '應用提醒'),
];

const noticeTypes = <String, List<NoticeTab>>{
  'mypost': [
    NoticeTab('mypost', '', '全部'),
    NoticeTab('mypost', 'post', '帖子'),
    NoticeTab('mypost', 'pcomment', '點評'),
    NoticeTab('mypost', 'activity', '活動'),
    NoticeTab('mypost', 'reward', '懸賞'),
    NoticeTab('mypost', 'goods', '商品'),
    NoticeTab('mypost', 'at', '提到我的'),
  ],
  'interactive': [
    NoticeTab('interactive', '', '全部'),
    NoticeTab('interactive', 'poke', '打招呼'),
    NoticeTab('interactive', 'friend', '好友'),
    NoticeTab('interactive', 'wall', '留言'),
    NoticeTab('interactive', 'comment', '評論'),
    NoticeTab('interactive', 'click', '挺你'),
    NoticeTab('interactive', 'sharenotice', '分享'),
  ],
};

/// 通知頁沒有手機版，Discuz 會回桌面模板，結構是 .nts > dl 而不是 li。
/// 內文連結指向 mod=redirect，主題 id 放在 ptid。
/// 首頁紅點：直接讀桌面版頁首的提醒選單，那裡有各類的未讀數，
/// 是論壇自己的權威來源（讀過就會歸零），比自己追 id 準得多。
///
/// - 私訊（消息）：`prompt_news_N` 的數字後綴
/// - 系統提醒／壇友互動／應用提醒：各自 `<span class="rq">N</span>`
/// - 新聽眾：`prompt_follower_N`
///
/// `#myprompt` 帶 class `yes` 代表「有新的東西」，當作保底。
Future<({int notice, int pm, Map<String, int> views})> fetchBadges() async {
  try {
    final doc = toDoc(await Api.instance.get('forum.php', desktop: true));
    return parsePromptCounts(doc);
  } on DiscuzException {
    return (notice: 0, pm: 0, views: const <String, int>{});
  }
}

int _classSuffix(dom.Element? el, String prefix) {
  final m = RegExp('${RegExp.escape(prefix)}(\\d+)').firstMatch(el?.className ?? '');
  return int.tryParse(m?.group(1) ?? '0') ?? 0;
}

/// 從頁首提醒選單解析未讀數。找不到選單就回全 0。
///
/// `views` 是各類提醒（system／interactive／app／mypost）各自的未讀數，
/// 給提醒頁高亮「是哪一類有新的」用。
({int notice, int pm, Map<String, int> views}) parsePromptCounts(
    dom.Document doc) {
  // 提醒選單在每個桌面頁的頁首都有；找不到就整份文件掃，別直接放棄
  final scope = doc.getElementById('myprompt_menu') ?? doc.documentElement;
  if (scope == null) return (notice: 0, pm: 0, views: const <String, int>{});

  // 私訊未讀：數字在 class 後綴（prompt_news_3），有些模板另外寫成 (N)
  final pmLink = scope.querySelector('a[href*="do=pm"]');
  var pm = _classSuffix(
      scope.querySelector('[class*="prompt_news_"]'), 'prompt_news_');
  final pmRq = int.tryParse(txt(pmLink?.querySelector('.rq'))) ?? 0;
  if (pmRq > pm) pm = pmRq;

  final follower =
      _classSuffix(scope.querySelector('[class*="prompt_follower_"]'), 'prompt_follower_');

  // 每個提醒分類的連結帶著 view=，未讀數在裡面的 .rq
  final views = <String, int>{};
  for (final a in scope.querySelectorAll('a[href*="do=notice"]')) {
    final view = param(attr(a, 'href'), 'view') ?? 'mypost';
    final rq = int.tryParse(txt(a.querySelector('.rq'))) ?? 0;
    if (rq > 0) views[view] = (views[view] ?? 0) + rq;
  }

  var notice = views.values.fold(0, (a, b) => a + b) + follower;
  // 保底：頁首說有新的（#myprompt 帶 class yes）但數字沒解出來，
  // 至少要讓鈴鐺亮起來 —— 這一段不能被「找不到選單」擋掉
  final yes = doc.getElementById('myprompt')?.classes.contains('yes') ?? false;
  if (yes && notice == 0 && pm == 0) notice = 1;

  return (notice: notice, pm: pm, views: views);
}

/// 提醒清單。
///
/// **注意：開這一頁論壇就會把該分類的提醒標成已讀**（未讀數歸零）。
/// 所以紅點絕對不能靠這支去「查有沒有新的」—— 那等於一邊查一邊清掉，
/// 使用者永遠看不到紅點。紅點請用 [fetchBadges]（只讀頁首，不會標已讀）。
Future<NoticeResult> fetchNotice({String view = 'mypost', String type = ''}) async {
  final q = 'home.php?mod=space&do=notice&view=$view'
      '${type.isEmpty ? '' : '&type=$type'}&forcemobile=1';
  final doc = await _page(q);
  final items = <NoticeItem>[];

  for (final dl in doc.querySelectorAll('.nts dl')) {
    final body = dl.querySelector('.ntc_body') ?? dl;
    final text = txt(body);
    if (text.isEmpty) continue;

    String link = '';
    for (final a in body.querySelectorAll('a')) {
      final h = attr(a, 'href');
      if (RegExp('ptid=|tid=|mod=viewthread').hasMatch(h)) {
        link = h;
        break;
      }
    }
    final av = absolute(attr(dl.querySelector('.avt img'), 'src'));
    // 提醒是論壇產生的系統文字（「XX 回覆了你的主題」），跟著介面語言走
    items.add(NoticeItem(
      id: attr(dl, 'notice'),
      avatar: av,
      uid: paramInt(av, 'uid') ??
          int.tryParse(RegExp(r'space-uid-(\d+)')
                  .firstMatch(attr(body.querySelector('a[href*="space-uid"]'), 'href'))
                  ?.group(1) ??
              ''),
      time: sys(txt(dl.querySelector('dt span'))),
      text: sys(text),
      tid: paramInt(link, 'ptid') ?? paramInt(link, 'tid'),
    ));
  }

  return NoticeResult(
    items: items,
    message: items.isEmpty ? (noticeMessage(doc) ?? '目前沒有新通知') : null,
  );
}

/// 私訊列表：li > a 內是 .avatar_img / .time / .num / .name / .grey，
/// 不是一般的 h4+p 版型
Future<PmListResult> fetchPmList() async {
  // 一定要用桌面版。手機版的私訊列表**沒有未讀標記**——每則對話長得
  // 一模一樣，看不出哪些沒讀。桌面版才會在有新訊息的對話 <dl> 上掛
  // `newpm` class，那是唯一可靠的未讀依據（會一直留到該對話被點開）。
  final html = await Api.instance.get('home.php?mod=space&do=pm', desktop: true);
  final doc = toDoc(html);
  final items = <PmItem>[];

  for (final dl in doc.querySelectorAll('dl[id^="pmlist_"]')) {
    // 對方 uid：刪除用的核取方塊 value 最穩，退而求其次抓回覆連結
    final box = dl.querySelector('input[name="deletepm_deluid[]"]');
    var touid = int.tryParse(attr(box, 'value'));
    touid ??= paramInt(
        attr(dl.querySelector('a[href*="touid="]'), 'href'), 'touid');
    if (touid == null) continue;

    // 未讀＝這則對話的 <dl> 有 newpm class（不是每則都有的 newpm_avt 圖示，
    // 那個是靠 class 用 CSS 顯示/隱藏的，一直都在）
    final unread = dl.classes.contains('newpm') ? 1 : 0;

    // 預覽文字是 .pm_c 裡第一個 <br> 之後的那段文字節點
    final body = dl.querySelector('.pm_c');
    var preview = '';
    if (body != null) {
      var seenBr = false;
      for (final node in body.nodes) {
        if (node is dom.Element && node.localName == 'br') {
          if (seenBr) break;
          seenBr = true;
        } else if (seenBr && node is dom.Text) {
          final t = node.text.trim();
          if (t.isNotEmpty) {
            preview = t;
            break;
          }
        }
      }
    }

    final timeSpan = dl.querySelector('.xg1 span[title]');
    items.add(PmItem(
      touid: touid,
      name: txt(dl.querySelector('.xw1')),
      last: preview,
      time: attr(timeSpan, 'title').isNotEmpty
          ? attr(timeSpan, 'title')
          : txt(dl.querySelector('.xg1')),
      avatar: absolute(attr(dl.querySelector('.avt img'), 'src')),
      unread: unread,
    ));
  }
  return PmListResult(items: items, message: items.isEmpty ? '目前沒有私訊' : null);
}

/// 對話內容：.self_msg（自己）與 .friend_msg（對方），內文在 .dialog_t
Future<PmChat> fetchPmChat(int touid) async {
  final doc = await _page('home.php?mod=space&do=pm&subop=view&touid=$touid');
  final msgs = <PmMessage>[];

  for (final box in doc.querySelectorAll('.msgbox > div')) {
    final mine = box.classes.contains('self_msg');
    if (!mine && !box.classes.contains('friend_msg')) continue;
    final body = box.querySelector('.dialog_t');
    if (body == null) continue;
    final t = txt(body);
    if (t.isEmpty && body.querySelector('img') == null) continue;
    msgs.add(PmMessage(
      html: sanitizeContent(body),
      text: t,
      avatar: absolute(attr(box.querySelector('.avat img'), 'src')),
      time: txt(box.querySelector('.date')),
      mine: mine,
    ));
  }

  final form = doc.querySelector('#pmform');
  return PmChat(
    touid: touid,
    title: txt(doc.querySelector('header h1')),
    messages: msgs,
    pmid: param(attr(form, 'action'), 'pmid') ?? '',
    formhash: attr(doc.querySelector('#pmform input[name="formhash"]'), 'value'),
  );
}

/// 有 pmid 就沿用該對話的端點，語意跟網頁版一致
Future<SubmitResult> sendPm(int touid, String message,
    {String pmid = '', String formhash = ''}) async {
  if (formhash.isEmpty) await _ensureFormhash();
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final url = pmid.isNotEmpty
      ? 'home.php?mod=spacecp&ac=pm&op=send&pmid=$pmid&daterange=0&pmsubmit=yes'
      : 'home.php?mod=spacecp&ac=pm&op=send&pmsubmit=yes&infloat=yes';

  final html = await Api.instance.post(url, {
    'formhash': hash,
    'message': message,
    'pmsubmit': 'true',
    'touid': '$touid',
  });
  return _submitResult(html, '傳送');
}

/* ─────────────── 個人中心 ─────────────── */

Future<MeData> fetchMe(int uid) async {
  final doc = await _page('home.php?mod=space&uid=$uid&do=profile&mycenter=1');
  final title = txt(doc.querySelector('.user_avatar h2'));
  return MeData(
    uid: uid,
    name: title.replaceFirst(RegExp(r'Lvl\..*$'), '').trim(),
    // 只抓數字會把「Lvl. 7 ✓」的勾與「Lvl. 10 · I」的羅馬數字吃掉，
    // 那是用戶組的一部分，整段留著
    level: RegExp(r'Lvl\..*$').firstMatch(title)?.group(0)?.trim() ?? '',
    avatar: avatarUrl(uid),
  );
}

/// 個人資料：改用手機版的結構化欄位。
///
/// 之前是把整頁 sanitize 後丟出來，連頁尾（自己的暱稱、登出連結）都被帶進去，
/// 所以看別人的資料時最下面會冒出自己的資訊。
Future<ProfileData> fetchProfile(int uid) async {
  // 手機版只有九項積分，擴展角色組／勳章／管理的版塊／已加入群組全都只有桌面模板才有。
  // 走 desktop:true —— 光是不帶 mobile=2 沒用，Discuz 會依 iPhone UA 自動轉手機版
  final html = await Api.instance
      .get('home.php?mod=space&uid=$uid&do=profile', desktop: true);
  return parseProfile(toDoc(html), uid);
}

/// 純解析，測試直接餵 fixture 用
ProfileData parseProfile(dom.Document doc, int uid) {
  final root = doc.querySelector('.u_profile') ?? doc.body!;

  // 標題：`<h2>名字<img alt=online><span class="xw0">(UID: …)</span></h2>`
  dom.Element? header;
  for (final h in root.querySelectorAll('h2')) {
    if (h.querySelector('.xw0') != null) {
      header = h;
      break;
    }
  }
  final name = header == null
      ? ''
      : txt(header).replaceFirst(txt(header.querySelector('.xw0')), '').trim();

  // 積分在「统计信息」區塊，比手機版多了已用空間
  final credits = <CreditItem>[];
  final psts = doc.querySelector('#psts');
  for (final li in psts?.querySelectorAll('li') ?? const <dom.Element>[]) {
    final em = li.querySelector('em');
    if (em == null) continue;
    final label = txt(em);
    final value = txt(li).replaceFirst(label, '').trim();
    if (label.isNotEmpty) credits.add(CreditItem(label, value));
  }

  var level = '';
  final roles = <String>[];
  final fields = <ProfileField>[];
  final stats = <ProfileLink>[];

  for (final li in root.querySelectorAll('li')) {
    final em = li.querySelector('em');
    if (em == null) continue;
    if (psts != null && _within(li, psts)) continue; // 已經進 credits 了

    final label = txt(em).replaceAll(' ', '').trim();
    final value = txt(li).replaceFirst(txt(em), '').trim();

    // 統計信息那列是一排連結（好友數／記錄數／日誌數／相冊數／回帖數／主題數）
    if (li.querySelector('a[href*="from=space"]') != null) {
      for (final a in li.querySelectorAll('a')) {
        final t = txt(a);
        if (t.isNotEmpty) stats.add(ProfileLink(t, url: absolute(attr(a, 'href'))));
      }
      continue;
    }

    if (label == '用户组' || label == '用戶組') {
      level = value;
      continue;
    }
    if (label.startsWith('扩展用户组') || label.startsWith('擴展用戶組')) {
      // 多個角色是用逗號分隔的 <font>，例如「GM活动员,战士 · I」
      roles.addAll(value.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
      continue;
    }
    if (label.isNotEmpty && value.isNotEmpty) {
      fields.add(ProfileField(label, value));
    }
  }

  final medals = <Medal>[];
  final sections = <ProfileSection>[];
  for (final box in root.querySelectorAll('.pbm')) {
    final h = box.querySelector('h2');
    if (h == null) continue;
    final heading = txt(h);
    if (heading.isEmpty || h.querySelector('.xw0') != null) continue; // 標題區塊

    if (heading.contains('勋章') || heading.contains('勳章')) {
      for (final img in box.querySelectorAll('img')) {
        final src = absolute(attr(img, 'src'));
        if (src.isEmpty) continue;
        medals.add(parseMedal(src, attr(img, 'alt'), attr(img, 'tip')));
      }
      continue;
    }
    if (heading.contains('活跃概况') || heading.contains('统计信息')) continue;

    // 管理以下版块／已加入群组…每個人有哪些區塊都不同，所以通用解析
    final links = <ProfileLink>[];
    for (final a in box.querySelectorAll('a')) {
      final t = txt(a);
      if (t.isEmpty) continue;
      final href = attr(a, 'href');
      links.add(ProfileLink(
        t,
        fid: int.tryParse(RegExp(r'(?:forum|group)-(\d+)').firstMatch(href)?.group(1) ?? '') ??
            paramInt(href, 'fid'),
        url: absolute(href),
      ));
    }
    if (links.isEmpty) continue;
    sections.add(ProfileSection(title: heading, links: links));
  }

  return ProfileData(
    uid: uid,
    name: name,
    avatar: avatarUrl(uid, size: 'big'),
    level: level,
    credits: credits,
    // 只有看自己的資料才會出現「編輯個人資料」的連結
    isSelf: doc.querySelector('a[href*="mod=spacecp"][href*="ac=profile"]') != null,
    online: header?.querySelector('img[alt="online"]') != null,
    roles: roles,
    fields: fields,
    sections: sections,
    medals: medals,
    stats: stats,
  );
}

/// 勳章的 `tip` 是一段被跳脫過的 HTML：
/// `<h4><b>等级 Max</b>黑暗之魂系列</h4><p>說明…</p><div class='wode_shuxing'><p>回帖 血液 +1</p></div>`
///
/// 等級和名字之間沒有空白，用正則硬切會把「Max黑暗之魂系列」黏成一塊，
/// 所以照結構拆：`<b>` 是等級、`<h4>` 剩下的是名字、`<p>` 是說明。
Medal parseMedal(String image, String alt, String tip) {
  if (tip.isEmpty) return Medal(image: image, name: zh(alt));

  final doc = toDoc('<div>$tip</div>');
  final h4 = doc.querySelector('h4');
  final b = h4?.querySelector('b');
  final level = txt(b).replaceFirst(RegExp(r'^等[级級]\s*'), '').trim();
  final name = h4 == null
      ? zh(alt)
      : txt(h4).replaceFirst(txt(b), '').trim();

  final effects = <String>[];
  for (final p in doc.querySelectorAll('.wode_shuxing p')) {
    final t = txt(p);
    if (t.isNotEmpty) effects.add(t);
  }

  final desc = <String>[];
  for (final p in doc.querySelectorAll('p')) {
    if (_within(p, doc.querySelector('.wode_shuxing') ?? p)) continue;
    final t = txt(p);
    if (t.isNotEmpty) desc.add(t);
  }

  return Medal(
    image: image,
    name: name.isEmpty ? zh(alt) : name,
    level: level,
    desc: desc.join('\n'),
    effects: effects,
  );
}

/// node 是不是在 ancestor 底下
bool _within(dom.Element node, dom.Element ancestor) {
  for (var p = node.parent; p != null; p = p.parent) {
    if (identical(p, ancestor)) return true;
  }
  return false;
}

/// 回帖獎勵與附件都只在桌面模板有（手機版整塊被拿掉），所以另外抓一次桌面頁。
/// 一次抓齊，不要為了兩件事各請求一遍。
Future<ThreadExtras> fetchThreadExtras(int tid, {int page = 1}) async {
  final html = await Api.instance.get(
    'forum.php?mod=viewthread&tid=$tid&page=$page',
    desktop: true,
  );
  final doc = toDoc(html);
  return ThreadExtras(
    prize: parseThreadPrize(doc),
    attachments: parseAttachments(doc),
  );
}

ThreadPrize? parseThreadPrize(dom.Document doc) {
  final top = doc.querySelector('#pl_top');
  if (top == null) return null;
  final icon = top.querySelector('img[alt*="奖励"], img[alt*="獎勵"]');
  if (icon == null) return null;
  final pool = txt(top.querySelector('strong'));
  // #pl_top 第一列是空的廣告列，規則在後面那個有字的 td.plc
  final rule = top
      .querySelectorAll('td.plc')
      .map(txt)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  if (pool.isEmpty && rule.isEmpty) return null;
  return ThreadPrize(pool: pool, rule: rule);
}

/// 附件有三種長相，只認一種會漏掉一大半：
///
/// * `dl.tattl`（不含 `.attm`）—— 帖尾那塊列出來的檔案
/// * `dl.tattl.attm` —— 「更多圖片」裡的圖片附件，內文已經顯示過，要排除
/// * `<span id="attach_NNN">` —— 夾在內文中間的附件，很常見
///
/// 買過沒買過看連結：`mod=attachment` 是可以直接下載，
/// `action=attachpay` 是還要先付錢。
List<Attachment> parseAttachments(dom.Document doc) {
  final out = <Attachment>[];
  final seen = <String>{};

  void add(Attachment a) {
    if (a.name.isEmpty) return;
    final key = '${a.name}|${a.url}';
    if (!seen.add(key)) return;
    out.add(a);
  }

  // 內文中間的附件
  for (final span in doc.querySelectorAll('span[id^="attach_"]')) {
    final a = span.querySelector('a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final tip = doc.getElementById('${attr(span, 'id')}_menu');
    final tipText = txt(tip);
    final record =
        attr(tip?.querySelector('a[href*="viewattachpayments"]'), 'href');
    add(Attachment(
      aid: int.tryParse(
              RegExp(r'attach_(\d+)').firstMatch(attr(span, 'id'))?.group(1) ??
                  '') ??
          paramInt(record, 'aid'),
      name: txt(a),
      url: absolute(href),
      icon: absolute(attr(span.previousElementSibling, 'src')),
      info: txt(span.querySelector('em')).replaceAll(RegExp(r'^\(|\)$'), ''),
      price: RegExp(r'售价[:：]\s*([^\s\[]+)').firstMatch(tipText)?.group(1) ?? '',
      permission:
          RegExp(r'阅读权限[:：]\s*(\S+)').firstMatch(tipText)?.group(1) ?? '',
      recordUrl: absolute(record),
      bought: href.contains('mod=attachment'),
    ));
  }

  // 帖尾那塊
  for (final dl in doc.querySelectorAll('dl.tattl')) {
    // 「更多圖片」的圖片附件，內文已經顯示過了
    if (dl.classes.contains('attm')) continue;

    final a = dl.querySelector('p.attnm a') ?? dl.querySelector('a');
    if (a == null) continue;
    final name = txt(a);
    if (name.isEmpty) continue;

    final icon = absolute(attr(dl.querySelector('dt img'), 'src'));
    if (RegExp(r'filetype/image').hasMatch(icon)) continue;

    var info = '';
    var price = '';
    var permission = '';
    for (final dd in dl.children.where((e) => e.localName == 'dd')) {
      for (final p in dd.children.where((e) => e.localName == 'p')) {
        if (p.classes.contains('attnm')) continue;
        final t = txt(p);
        if (t.isEmpty) continue;
        if (t.contains('售价') || t.contains('售價')) {
          price = txt(p.querySelector('strong'));
        } else if (info.isEmpty) {
          info = t;
          permission =
              RegExp(r'阅读权限[:：]\s*(\S+?)[,，]').firstMatch(t)?.group(1) ?? '';
        }
      }
    }

    final href = attr(a, 'href');
    final record =
        attr(dl.querySelector('a[href*="viewattachpayments"]'), 'href');
    add(Attachment(
      aid: paramInt(href, 'aid') ??
          paramInt(record, 'aid') ??
          int.tryParse(RegExp(r'aid(\d+)')
                  .firstMatch(attr(dl.querySelector('[id^="aid"]'), 'id'))
                  ?.group(1) ??
              ''),
      name: name,
      url: absolute(href),
      icon: absolute(icon),
      info: info,
      price: price,
      permission: permission,
      recordUrl: absolute(record),
      bought: href.contains('mod=attachment'),
    ));
  }

  return out;
}

/// 附件的純文字內容。
///
/// 論壇送 `application/octet-stream` 而且不帶 charset，瀏覽器只好用系統
/// 預設編碼去猜 —— 繁體中文系統會猜成 Big5，UTF-8 的檔案就變一片亂碼。
/// 自己抓下來解碼就不會有這個問題。
Future<String> fetchAttachmentText(String url) async {
  var path = url.replaceAll('&amp;', '&');
  if (path.startsWith(kOrigin)) path = path.substring(kOrigin.length);
  final bytes =
      await Api.instance.getBytes(path.replaceFirst(RegExp(r'^/'), ''));
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 舊檔案可能是 GBK，退而求其次別讓整段變問號
    return latin1.decode(bytes);
  }
}

/// 購買附件：先拿確認表單（作者、售價、購買後餘額），使用者確認後才送出。
/// 只有桌面模板有這個浮層
Future<AttachPay> fetchAttachPay(int aid, int tid) async {
  final xml = await Api.instance.get(
    'forum.php?mod=misc&action=attachpay&aid=$aid&tid=$tid'
    '&infloat=yes&handlekey=attachpay&inajax=1',
    desktop: true,
  );
  final doc = toDoc(_unwrapAjax(xml));
  final form = doc.querySelector('#attachpayform');
  if (form == null) {
    return AttachPay(message: noticeMessage(doc) ?? '拿不到購買資訊');
  }

  final rows = <({String label, String value})>[];
  var name = '';
  var author = '';
  for (final tr in form.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 2) continue;
    final label = txt(tds[0]);
    final value = txt(tds[1]);
    if (label.contains('附件')) {
      name = value;
    } else if (label.contains('作者') && !label.contains('所得')) {
      author = value;
    } else {
      rows.add((label: label, value: value));
    }
  }

  return AttachPay(
    name: name,
    author: author,
    rows: rows,
    formhash: attr(form.querySelector('input[name="formhash"]'), 'value'),
    action: attr(form, 'action'),
    aid: attr(form.querySelector('input[name="aid"]'), 'value'),
  );
}

Future<SubmitResult> submitAttachPay(AttachPay pay) async {
  if (!pay.ready) {
    return SubmitResult(ok: false, message: pay.message ?? '沒有購買表單');
  }
  final html = await Api.instance.post(
    '${pay.action.replaceAll('&amp;', '&')}&inajax=1',
    {
      'formhash': pay.formhash,
      'aid': pay.aid,
      'handlekey': 'attachpay',
      'paysubmit': 'true',
      'referer': '$kOrigin/',
    },
    desktop: true,
  );
  return _submitResult(html, '購買');
}

/// 加好友（論壇會回一個確認表單頁，成功與否看回應訊息）
Future<SubmitResult> addFriend(int uid) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=friend&op=add&uid=$uid&handlekey=a_friend_$uid&formhash=$_formhash');
  return _submitResult(html, '加好友');
}

/// 打招呼的表單：14 種動作＋一句可選的話（最多 10 字）。
/// 動作清單直接讀論壇的表單，論壇加減動作我們就跟著變。
Future<PokeForm> fetchPokeForm(int uid) async {
  final xml = await Api.instance
      .get('home.php?mod=spacecp&ac=poke&op=send&uid=$uid&inajax=1', desktop: true);
  final doc = toDoc(_unwrapAjax(xml));

  final options = <PokeOption>[];
  var defaultId = 0;
  for (final input in doc.querySelectorAll('input[name="iconid"]')) {
    final id = int.tryParse(attr(input, 'value'));
    if (id == null) continue;
    // 名稱是 <label> 裡除了圖片以外的文字
    final label = input.parent;
    final name = sys(txt(label).trim());
    final icon = absolute(attr(label?.querySelector('img'), 'src'));
    if (attr(input, 'checked').isNotEmpty || input.attributes.containsKey('checked')) {
      defaultId = id;
    }
    options.add(PokeOption(id: id, name: name, icon: icon));
  }

  return PokeForm(
    uid: uid,
    options: options,
    defaultIconId: defaultId,
    formhash: formhashOf(doc) ?? _formhash ?? '',
    noteHint: sys(txt(doc.querySelector('.xg1'))),
  );
}

/// 送出打招呼。[fromNotice] 代表是從提醒頁回招呼（論壇會順手清掉那則提醒）
Future<SubmitResult> sendPoke(
  int uid, {
  int iconId = 0,
  String note = '',
  String formhash = '',
  bool fromNotice = false,
}) async {
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=poke&op=send&uid=$uid&inajax=1',
    {
      'formhash': hash,
      'iconid': '$iconId',
      'note': note,
      'pokesubmit': 'true',
      'pokesubmit_btn': 'true',
      if (fromNotice) 'from': 'notice',
    },
    desktop: true,
  );
  return _submitResult(html, '打招呼');
}

/// 忽略某人的招呼（提醒頁的「忽略」）。論壇是兩步：先拿確認表單再 POST
Future<SubmitResult> ignorePoke(int uid) => confirmAndSubmit(
      'home.php?mod=spacecp&ac=poke&op=ignore&uid=$uid&handlekey=noticeignore',
      '忽略招呼',
    );

/// 刪掉一則提醒。任何分類都適用，論壇回「操作成功」
Future<SubmitResult> deleteNotice(String noticeId) async {
  if (noticeId.isEmpty) {
    return const SubmitResult(ok: false, message: '這則提醒沒有編號，無法忽略');
  }
  final html = await Api.instance.get(
      'home.php?mod=misc&ac=ajax&op=delnotice&inajax=1&id=$noticeId',
      desktop: true);
  return _submitResult(html, '忽略提醒');
}

/// 收藏頁用的是 .fav_list，和主題列表不同版型
List<ThreadItem> parseFavList(dom.Document doc) {
  final out = <ThreadItem>[];
  for (final li in doc.querySelectorAll('.fav_list li')) {
    final a = li.querySelector('a.favTit');
    if (a == null) continue;
    final tid = paramInt(attr(a, 'href'), 'tid');
    if (tid == null) continue;
    out.add(ThreadItem(
      tid: tid,
      title: txt(a),
      date: txt(li.querySelector('p')).replaceFirst(RegExp(r'^删除\s*'), ''),
      favid: paramInt(attr(li.querySelector('a[href*="op=delete"]'), 'href'), 'favid'),
    ));
  }
  return out;
}

/// 我的主題／回覆／點評都走 do=thread，靠 type 區分
const myPostTypes = <({String type, String name})>[
  (type: 'thread', name: '主題'),
  (type: 'reply', name: '回覆'),
  (type: 'pcomment', name: '點評'),
];

Future<ListPage> _myList(int uid, String doType, int page, {String type = ''}) async {
  final q = <String, String>{'mod': 'space', 'uid': '$uid', 'do': doType, 'view': 'me'};
  if (doType == 'favorite') {
    q['type'] = 'thread';
  } else if (type.isNotEmpty) {
    q['type'] = type;
  }
  if (page > 1) q['page'] = '$page';
  final doc = await _page('home.php?${_qs(q)}');

  final list = doType == 'favorite' ? parseFavList(doc) : parseThreadList(doc);
  if (list.isNotEmpty) {
    return ListPage(list: list, pager: parsePager(doc, current: page));
  }

  final seen = <int, ThreadItem>{};
  for (final a in doc.querySelectorAll('a[href*="mod=viewthread"], a[href*="/thread-"], a[href*="ptid="]')) {
    final href = attr(a, 'href');
    final tid = paramInt(href, 'tid') ??
        paramInt(href, 'ptid') ??
        int.tryParse(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1) ?? '');
    final title = txt(a);
    if (tid != null && title.isNotEmpty) {
      seen.putIfAbsent(tid, () => ThreadItem(tid: tid, title: title));
    }
  }
  return ListPage(
      list: seen.values.toList(), pager: parsePager(doc, current: page));
}

/// 收藏的版塊：和收藏帖子同一種 .fav_list 版型，只是連結指向 forumdisplay
Future<List<SubForum>> fetchFavoriteForums(int uid, {int page = 1}) async {
  final q = 'home.php?mod=space&uid=$uid&do=favorite&view=me&type=forum'
      '${page > 1 ? '&page=$page' : ''}';
  final doc = await _page(q);
  final out = <SubForum>[];
  for (final li in doc.querySelectorAll('.fav_list li')) {
    final a = li.querySelector('a.favTit');
    final fid = paramInt(attr(a, 'href'), 'fid');
    if (a == null || fid == null) continue;
    out.add(SubForum(
      fid: fid,
      name: txt(a),
      favid: paramInt(attr(li.querySelector('a[href*="op=delete"]'), 'href'), 'favid'),
      favTime: txt(li.querySelector('p')).replaceFirst(RegExp(r'^删除\s*'), ''),
    ));
  }
  return out;
}

Future<ListPage> fetchFavorites(int uid, {int page = 1}) => _myList(uid, 'favorite', page);

/// 我的主題／回覆／點評共用 do=thread，type 決定看哪一種
Future<ListPage> fetchMyPosts(int uid, {String type = 'thread', int page = 1}) =>
    _myList(uid, 'thread', page, type: type);

/// 我的主題／回覆／點評。手機版只給標題，桌面版連版塊、作者、回覆內容
/// 與那一樓的 pid 都有，所以走桌面模板。
Future<ListPage> fetchGuideMine({
  String type = 'thread',
  int page = 1,
  int fid = 0,
}) async {
  final q = StringBuffer('forum.php?mod=guide&view=my&type=$type');
  if (fid > 0) q.write('&fid=$fid');
  if (page > 1) q.write('&page=$page');

  final html = await Api.instance.get(q.toString(), desktop: true);
  final doc = toDoc(html);
  if (isLoginWall(doc) || isRedirectToLogin(doc, html)) {
    return const ListPage(list: [], message: '要先登入才看得到');
  }

  final list = <ThreadItem>[];
  for (final body in doc.querySelectorAll('tbody')) {
    final id = attr(body, 'id');
    final tid = int.tryParse(
        RegExp(r'normalthread_(\d+)').firstMatch(id)?.group(1) ?? '');
    if (tid == null) continue;

    final a = body.querySelector('th a.xst') ?? body.querySelector('th a');
    if (a == null) continue;
    final bys = body.querySelectorAll('td.by');
    final num = body.querySelector('td.num');

    // 我的回覆內容在下一個 tbody（class="bw0_all"）
    var myReply = '';
    int? myPid;
    final next = body.nextElementSibling;
    final replyLink = next?.querySelector('.tl_reply a');
    if (replyLink != null) {
      myReply = txt(replyLink);
      myPid = paramInt(attr(replyLink, 'href'), 'pid');
    }

    final forumLink = body.querySelector('td.by a[href*="forum-"]') ??
        body.querySelector('td.by a[href*="group-"]');

    list.add(ThreadItem(
      tid: tid,
      title: txt(a),
      forumName: txt(forumLink),
      fid: int.tryParse(
          RegExp(r'(?:forum|group)-(\d+)')
                  .firstMatch(attr(forumLink, 'href'))
                  ?.group(1) ??
              ''),
      author: bys.length > 1 ? txt(bys[1].querySelector('cite')) : '',
      date: bys.length > 1 ? txt(bys[1].querySelector('em')) : '',
      replies: int.tryParse(txt(num?.querySelector('a'))) ?? 0,
      views: int.tryParse(txt(num?.querySelector('em'))) ?? 0,
      myReply: myReply,
      myPid: myPid,
    ));
  }

  return ListPage(
    list: list,
    pager: parsePager(doc, current: page),
    message: list.isEmpty ? (noticeMessage(doc) ?? '這裡沒有東西') : null,
  );
}

/// 我的主題／回覆這幾頁只給「上一頁／下一頁」，沒有總頁數。想顯示成
/// 「1 / N」就得自己往後翻，沿著 a.nxt 一路數到最後一頁。
///
/// [fromPage] 傳目前這頁的下一頁（呼叫端已知目前這頁還有下一頁）。
/// 最多翻 30 頁，避免資料異常時無限翻。
Future<int> resolveGuideTotal({
  String type = 'thread',
  int fid = 0,
  required int fromPage,
}) async {
  var page = fromPage;
  for (var i = 0; i < 30; i++) {
    final r = await fetchGuideMine(type: type, page: page, fid: fid);
    if (!r.pager.hasNext) return page;
    page++;
  }
  return page;
}

/// 那一樓在第幾頁。論壇的 findpost 會轉到正確的頁，從轉址結果反推
Future<int> resolvePostPage(int tid, int pid) async {
  final html = await Api.instance
      .get('forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid');
  // 轉址後的頁面自己會標出目前頁數
  final doc = toDoc(html);
  final p = parsePager(doc).page;
  return p > 0 ? p : 1;
}

Future<SubmitResult> favoriteThread(int tid) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&handlekey=favoritethread&formhash=$_formhash');
  return _submitResult(html, '收藏');
}

/// 論壇的刪除類動作都是兩步驟：先 GET 拿一張確認表單，再 POST 送出。
/// 只做第一步的話只會拿到「您确定要…吗？」，什麼都沒做。
/// 表單裡的 formhash 跟頁面上那個不一樣，一定要用回傳的這個。
///
/// [url] 是論壇連結上寫的那個網址（`op=delete&...&handlekey=xxx`）。
Future<SubmitResult> confirmAndSubmit(String url, String what) async {
  var path = url.replaceAll('&amp;', '&');
  if (path.startsWith(kOrigin)) path = path.substring(kOrigin.length);
  path = path.replaceFirst(RegExp(r'^/'), '');

  final key = param(path, 'handlekey') ?? '';
  final sep = path.contains('?') ? '&' : '?';
  final form =
      await Api.instance.get('$path${sep}infloat=yes&inajax=1', desktop: true);
  final doc = toDoc(_unwrapAjax(form));
  final formEl = doc.querySelector('form');
  final hash = attr(doc.querySelector('input[name="formhash"]'), 'value');
  if (hash.isEmpty) return _submitResult(form, what);

  // 送出的目標是表單自己的 action，不見得跟剛剛那個網址一樣
  final action = attr(formEl, 'action').replaceAll('&amp;', '&');
  final target = action.isEmpty ? path : action;

  // 表單裡本來就有的隱藏欄位全帶上，少一個論壇就當作沒送
  final fields = <String, String>{};
  for (final input
      in formEl?.querySelectorAll('input') ?? const <dom.Element>[]) {
    final name = attr(input, 'name');
    if (name.isEmpty) continue;
    fields[name] = attr(input, 'value');
  }
  fields['formhash'] = hash;
  if (key.isNotEmpty) fields['handlekey'] = key;
  // 確認鈕本身也是欄位，論壇靠它判斷是不是真的按了
  for (final b in formEl?.querySelectorAll('button') ?? const <dom.Element>[]) {
    final name = attr(b, 'name');
    if (name.isNotEmpty) fields[name] = attr(b, 'value').isEmpty ? 'true' : attr(b, 'value');
  }

  final html = await Api.instance.post(
      '$target${target.contains('?') ? '&' : '?'}inajax=1', fields,
      desktop: true);
  return _submitResult(html, what);
}

Future<SubmitResult> unfavorite(int favid) => confirmAndSubmit(
      'home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid'
      '&handlekey=a_delete_$favid',
      '取消收藏',
    );


/* ─────────────── 積分變化（勳章觸發） ─────────────── */

/// 論壇會在頁面裡輸出權威對照，例如
/// creditnotice = '1|旅程|里,2|金币|枚,3|血液|滴,...'
/// 注意順序和積分頁上的排列不同，照畫面順序猜會標錯名稱。
/// 積分名稱表。**key 是論壇給的積分 ID，不是順序** —— cookie 也是照 ID 定位的
Map<int, ({String name, String unit})> _creditNames = const {};

void _captureCreditNames(String html) {
  // creditnotice = '1|旅程|里,2|金币|枚,3|血液|滴,…'
  final m = RegExp(r"creditnotice\s*=\s*'([^']+)'").firstMatch(html);
  if (m == null) return;
  final out = <int, ({String name, String unit})>{};
  for (final part in m.group(1)!.split(',')) {
    final f = part.split('|');
    if (f.length < 3) continue;
    final id = int.tryParse(f[0]);
    if (id == null) continue;
    out[id] = (name: sys(f[1]), unit: sys(f[2]));
  }
  if (out.isNotEmpty) _creditNames = out;
}

/// 只給測試用：目前解出來的積分名稱表
List<String> get creditNamesDebug =>
    [for (final e in _creditNames.entries) '${e.key}=${e.value.name}(${e.value.unit})'];

/// 讀 `<cookiepre>_creditnotice`，解出這次操作得到的積分。
///
/// cookie 是 `總積分D變化1D變化2…D變化8D uid`，一共十格。
/// **要用積分 ID 定位，不是照名稱表的順序數過去** —— 論壇自己的
/// `creditShow()` 就是 `for(i=1;i<=8;i++) notice[i]`，第 0 格是總積分。
/// 照順序數會整串位移一格（金幣的變化被標成血液、血液被標成追隨…）。
///
/// 最後一格必須等於自己的 uid，否則這份 cookie 不是給這個帳號的，直接丟掉。
Future<List<CreditChange>> consumeCreditNotice({int? uid}) async {
  final raw = await Api.instance.cookieEndingWith('_creditnotice');
  // 讀完就清掉，跟網頁版一樣。不清的話內建瀏覽器每開一頁都會再跳一次
  await Api.instance.clearCookieEndingWith('_creditnotice');
  if (raw == null || raw.isEmpty) return const [];
  return parseCreditNotice(raw, uid: uid);
}

/// 純解析，測試直接餵 cookie 字串用
List<CreditChange> parseCreditNotice(String raw, {int? uid}) {
  if (_creditNames.isEmpty) return const [];

  final parts = raw.split('D');
  if (parts.length < 2) return const [];
  if (uid != null && int.tryParse(parts.last) != uid) return const [];

  final out = <CreditChange>[];
  for (final entry in _creditNames.entries) {
    final id = entry.key;
    if (id < 0 || id >= parts.length - 1) continue;
    final v = int.tryParse(parts[id]) ?? 0;
    if (v != 0) out.add(CreditChange(entry.value.name, v, entry.value.unit));
  }
  return out;
}

/// 只給測試用：直接餵 creditnotice 那串名稱表
void captureCreditNamesForTest(String spec) =>
    _captureCreditNames("creditnotice = '$spec'");

/// 開內建瀏覽器前先把積分提示清掉，不然論壇會把上一次操作的變化
/// 再跳一次（而且每開一頁跳一次）
Future<void> dismissCreditNotice() async {
  await Api.instance.clearCookieEndingWith('_creditnotice');
  await Api.instance.clearCookieEndingWith('_creditrule');
}

/// 這次積分是哪個動作給的（「发表回复」「每天登录」…）。
/// 論壇顯示在積分變化前面，跟 creditnotice 是同一批 cookie。
Future<String> consumeCreditRule() async {
  final raw = await Api.instance.cookieEndingWith('_creditrule');
  await Api.instance.clearCookieEndingWith('_creditrule');
  if (raw == null || raw.isEmpty) return '';
  // cookie 是 URL 編碼過的，規則之間用 tab 分隔
  try {
    return zh(Uri.decodeComponent(raw.replaceAll('+', ' '))
        .replaceAll('\t', ' ')
        .trim());
  } catch (_) {
    return '';
  }
}

/* ─────────────── 記錄廣場 ─────────────── */

/// 只有 all 是公開的；we/me 需要帳號
const doingViews = <({String key, String name, bool needsLogin})>[
  (key: 'all', name: '隨便看看', needsLogin: false),
  (key: 'we', name: '我和好友', needsLogin: true),
  (key: 'me', name: '我的記錄', needsLogin: true),
];

/// 記錄沒有手機模板。桌面版才把每則回覆連同時間、縮排（版主回覆）
/// 都內嵌在頁面裡，手機版的回覆是空的要另外 ajax，所以走桌面版。
Future<DoingPage> fetchDoing({String view = 'all', int page = 1}) async {
  final doc = await _page('home.php?mod=space&do=doing&view=$view'
      '&mobile=no${page > 1 ? '&page=$page' : ''}');
  return parseDoingPage(doc, page: page);
}

DoingPage parseDoingPage(dom.Document doc, {int page = 1}) {
  final items = <DoingItem>[];

  for (final dl in doc.querySelectorAll('.xld dl')) {
    final id = attr(dl, 'id');
    final doid = int.tryParse(RegExp(r'dl(\d+)$').firstMatch(id)?.group(1) ?? '');
    if (doid == null) continue;

    final body = dl.querySelector('.ptm');
    final link = body?.querySelector('a');
    final href = attr(link, 'href');
    final span = body?.querySelector('span');

    // 桌面版的回覆在 dd.cmt > ul > li，帶時間、可縮排（版主回覆別人）
    final comments = <DoingComment>[];
    for (final li in dl.querySelectorAll('dd.cmt li')) {
      final who = li.querySelector('a.lit');
      if (who == null) continue;
      final del = li.querySelector('a[href*="op=delete"]');
      final cid = paramInt(attr(del, 'href'), 'id') ??
          int.tryParse(
              RegExp(r'docomment_form\(\d+,\s*(\d+)')
                      .firstMatch(li.innerHtml)
                      ?.group(1) ??
                  '');
      // 論壇本來就把時間包在括號裡，別再套一層
      final time = txt(li.querySelector('span.xg1'))
          .replaceAll(RegExp(r'^\(|\)$'), '');
      var text = txt(li);
      for (final drop in [txt(who), '($time)', time, '回复', '删除', '回覆', '刪除']) {
        if (drop.isNotEmpty) text = text.replaceFirst(drop, '');
      }
      // 縮排一層＝回覆別人的那一則（padding-left / dtls）
      final style = attr(li, 'style');
      final indented = li.classes.contains('dtls') ||
          RegExp(r'padding-left:\s*([1-9])').hasMatch(style);
      comments.add(DoingComment(
        cid: cid ?? 0,
        author: txt(who),
        uid: paramInt(attr(who, 'href'), 'uid') ??
            int.tryParse(
                RegExp(r'space-uid-(\d+)')
                        .firstMatch(attr(who, 'href'))
                        ?.group(1) ??
                    ''),
        text: text.replaceFirst(RegExp(r'^[:：]\s*'), '').trim(),
        time: time,
        isReply: indented,
        deleteUrl: absolute(attr(del, 'href')),
      ));
    }

    // 自己那則記錄的刪除連結，id 是空的
    var selfDelete = '';
    for (final a in dl.querySelectorAll('a[href*="ac=doing"][href*="op=delete"]')) {
      final h = attr(a, 'href');
      if ((param(h, 'id') ?? '').isEmpty) selfDelete = absolute(h);
    }

    // 時間優先取 title 上的絕對時間（「7 天前」不好對照）
    final timeEl = dl.querySelector('.ptn .y span[title]');
    items.add(DoingItem(
      doid: doid,
      uid: int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(href)?.group(1) ?? '') ??
          paramInt(href, 'uid'),
      name: txt(link),
      avatar: absolute(attr(dl.querySelector('.avt img'), 'src')),
      html: span == null ? '' : sanitizeContent(span),
      message: txt(span),
      time: attr(timeEl, 'title').isNotEmpty
          ? attr(timeEl, 'title')
          : txt(dl.querySelector('.ptn .y')),
      comments: comments,
      deleteUrl: selfDelete,
    ));
  }

  return DoingPage(
    items: items,
    formhash: formhashOf(doc) ?? '',
    pager: parsePager(doc, current: page),
  );
}

/// 回覆某則記錄。跟留言板、日誌評論同一支端點，只是 idtype 換成 doid
Future<SubmitResult> replyDoing(int doid, String message,
    {String formhash = ''}) async {
  if (formhash.isEmpty) await _ensureFormhash();
  final hash = formhash.isNotEmpty ? formhash : (_formhash ?? '');
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=comment&commentsubmit=yes'
    '&handlekey=doingcomment_$doid&inajax=1',
    {
      'formhash': hash,
      'message': message,
      'id': '$doid',
      'idtype': 'doid',
      'commentsubmit': 'true',
      'quickcomment': 'true',
      'handlekey': 'doingcomment_$doid',
    },
    desktop: true,
  );
  return _submitResult(html, '回覆');
}

Future<SubmitResult> postDoing(String message, {String formhash = ''}) async {
  if (formhash.isEmpty) await _ensureFormhash();
  final html = await Api.instance.post('home.php?mod=spacecp&ac=doing&view=all', {
    'message': message,
    'addsubmit': 'true',
    'formhash': formhash.isNotEmpty ? formhash : (_formhash ?? ''),
    'refer': 'home.php?mod=space&do=doing&view=all',
  });
  return _submitResult(html, '發布');
}


/* ─────────────── 評分 ─────────────── */

/// Discuz 的浮層端點回的是 `<root><![CDATA[ …HTML… ]]></root>`
/// ajax 回應包在 CDATA 裡，其他檔案也要用
String unwrapAjax(String xml) => _unwrapAjax(xml);

String _unwrapAjax(String xml) {
  final m = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(xml);
  return m?.group(1) ?? xml;
}

Future<RateForm> fetchRateForm({required int fid, required int tid, required int pid}) async {
  final xml = await Api.instance.get(
      'forum.php?mod=misc&action=rate&fid=$fid&tid=$tid&pid=$pid'
      '&infloat=yes&handlekey=rate&inajax=1&ajaxtarget=fwin_content_rate');
  final doc = toDoc(_unwrapAjax(xml));

  final options = <RateOption>[];
  for (final input in doc.querySelectorAll('input[name^="score"]')) {
    final field = attr(input, 'name');
    final row = _closestTag(input, 'tr');
    if (row == null) continue;
    final tds = row.querySelectorAll('td');
    if (tds.isEmpty) continue;

    final choices = <int>[];
    for (final li in row.querySelectorAll('ul li')) {
      final v = int.tryParse(txt(li).replaceAll(RegExp(r'[^0-9-]'), ''));
      if (v != null && v != 0) choices.add(v);
    }
    choices.sort();

    options.add(RateOption(
      field: field,
      name: txt(tds[0]),
      choices: choices,
      range: tds.length > 2 ? txt(tds[2]) : '',
      remaining: tds.length > 3 ? txt(tds[3]) : '',
    ));
  }

  return RateForm(
    options: options,
    reasons: doc.querySelectorAll('#reasonselect li').map(txt).where((r) => r.isNotEmpty).toList(),
    formhash: attr(doc.querySelector('input[name="formhash"]'), 'value'),
    tid: attr(doc.querySelector('input[name="tid"]'), 'value'),
    pid: attr(doc.querySelector('input[name="pid"]'), 'value'),
    referer: attr(doc.querySelector('input[name="referer"]'), 'value'),
    message: options.isEmpty ? (noticeMessage(doc) ?? txt(doc.body)) : null,
  );
}

dom.Element? _closestTag(dom.Element el, String tag) {
  dom.Element? cur = el.parent;
  while (cur != null) {
    if (cur.localName == tag) return cur;
    cur = cur.parent;
  }
  return null;
}

/// scores 只帶實際存在的欄位；低等級帳號缺項時硬塞會被論壇擋下
Future<SubmitResult> submitRate({
  required RateForm form,
  required Map<String, int> scores,
  String reason = '',
  bool notifyAuthor = false,
}) async {
  final body = <String, dynamic>{
    'formhash': form.formhash,
    'tid': form.tid,
    'pid': form.pid,
    'referer': form.referer,
    'handlekey': 'rate',
    'reason': reason,
    'ratesubmit': 'yes',
  };
  if (notifyAuthor) body['sendreasonpm'] = 'on';

  var any = false;
  for (final o in form.options) {
    final v = scores[o.field] ?? 0;
    body[o.field] = '$v';
    if (v != 0) any = true;
  }
  if (!any) return const SubmitResult(ok: false, message: '請先給一項分數');

  final html = await Api.instance
      .post('forum.php?mod=misc&action=rate&ratesubmit=yes&infloat=yes&inajax=1', body);
  final text = txt(toDoc(_unwrapAjax(html)).body);
  final ok = !RegExp('权限|不能|无法|失败|错误|超过|已经评分').hasMatch(text);
  return SubmitResult(ok: ok, message: text.isEmpty ? '評分完成' : text);
}

/// 已有的評分紀錄。手機版模板完全不顯示評分，桌面整頁又要 600KB 以上，
/// 所以用這個獨立端點按需載入。
Future<List<RateRecord>> fetchRatings({required int tid, required int pid}) async {
  // inajax=1 只回浮層內容（約 3.5KB），比 forcemobile 的 22KB、桌面整頁的 44KB 都輕
  final xml = await Api.instance
      .get('forum.php?mod=misc&action=viewratings&tid=$tid&pid=$pid&inajax=1');
  final doc = toDoc(_unwrapAjax(xml));

  // 論壇每一列只放一項積分，同一人同一次評分會出現好幾列。
  // 用「評分者 + 時間 + 理由」當鍵合併，畫面才不會被同一個人洗版。
  final merged = <String, RateRecord>{};
  final order = <String>[];

  for (final tr in doc.querySelectorAll('table.list tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 4) continue;
    final credit = txt(tds[0]);
    if (credit.isEmpty || credit == '积分') continue;

    final link = tds[1].querySelector('a');
    final name = txt(tds[1]);
    final uid = int.tryParse(
        RegExp(r'space-uid-(\d+)').firstMatch(attr(link, 'href'))?.group(1) ?? '');
    final rawTime = attr(tds[2].querySelector('span'), 'title');
    final time = rawTime.isNotEmpty ? rawTime : txt(tds[2]);
    final reason = txt(tds[3]);

    final key = '$uid|$time|$reason';
    final prev = merged[key];
    if (prev == null) {
      order.add(key);
      merged[key] = RateRecord(
        credits: [credit],
        name: name,
        uid: uid,
        time: time,
        reason: reason,
      );
    } else {
      merged[key] = RateRecord(
        credits: [...prev.credits, credit],
        name: prev.name,
        uid: prev.uid,
        time: prev.time,
        reason: prev.reason,
      );
    }
  }

  final out = [for (final k in order) merged[k]!];
  return out;
}


/* ─────────────── 編輯自己的帖子 ─────────────── */

/// 手機版模板沒有編輯連結，但端點是通的，而且回的是原始 BBCode
Future<EditForm> fetchEditForm({
  required int fid,
  required int tid,
  required int pid,
}) async {
  final html = await Api.instance
      .get('forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid');
  final doc = toDoc(html);
  _capture(doc, html);

  final subjectInput = doc.querySelector('input[name="subject"]');
  return EditForm(
    subject: attr(subjectInput, 'value'),
    message: doc.querySelector('textarea[name="message"]')?.text ?? '',
    formhash: attr(doc.querySelector('input[name="formhash"]'), 'value'),
    posttime: attr(doc.querySelector('input[name="posttime"]'), 'value'),
    fid: attr(doc.querySelector('input[name="fid"]'), 'value'),
    tid: attr(doc.querySelector('input[name="tid"]'), 'value'),
    pid: attr(doc.querySelector('input[name="pid"]'), 'value'),
    hasSubject: subjectInput != null,
    message2: noticeMessage(doc),
  );
}

Future<SubmitResult> submitEdit({
  required EditForm form,
  required String message,
  String subject = '',
}) async {
  final html = await Api.instance
      .post('forum.php?mod=post&action=edit&extra=&editsubmit=yes', {
    'formhash': form.formhash,
    'posttime': form.posttime,
    'fid': form.fid,
    'tid': form.tid,
    'pid': form.pid,
    'page': '',
    'editsubmit': 'yes',
    if (form.hasSubject) 'subject': subject,
    'message': message,
  });
  return _submitResult(html, '編輯');
}

/* ─────────────── 登入 / 登出 ─────────────── */

Future<Uint8List> seccodeImage(String idhash) => Api.instance.getBytes(
    'misc.php?mod=seccode&update=${DateTime.now().millisecondsSinceEpoch}&idhash=$idhash');

Future<LoginMeta> loginMeta() async {
  final html = await Api.instance.get('member.php?mod=logging&action=login');
  final doc = toDoc(html);
  final action = attr(doc.querySelector('#loginform'), 'action');
  final seccodehash = attr(doc.querySelector('input[name="seccodehash"]'), 'value');

  var meta = LoginMeta(
    formhash: formhashOf(doc, html) ?? '',
    loginhash: param(action, 'loginhash') ?? '',
    seccodehash: seccodehash,
    needSeccode: seccodehash.isNotEmpty,
    questions: doc
        .querySelectorAll('select[name="questionid"] option')
        .map((o) => SecurityQuestion(id: attr(o, 'value'), name: txt(o)))
        .toList(),
  );
  if (meta.needSeccode) {
    try {
      meta = meta.withImage(await seccodeImage(seccodehash));
    } on DiscuzException {
      // 驗證碼圖抓不到不該擋住整個登入頁，讓使用者按重新整理再試
    }
  }
  return meta;
}

String? _cleanError(String html) {
  final m = RegExp(r'<div class="alert_error">([\s\S]*?)</div>').firstMatch(html) ??
      RegExp(r"errorhandle_[^(]*\('([^']+)'").firstMatch(html);
  return m?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

Future<SubmitResult> login({
  required String username,
  required String password,
  required LoginMeta meta,
  String questionid = '0',
  String answer = '',
  String seccode = '',
}) async {
  final html = await Api.instance.post(
    'member.php?mod=logging&action=login&loginsubmit=yes&loginhash=${meta.loginhash}&inajax=0',
    {
      'formhash': meta.formhash,
      'referer': '$kOrigin/forum.php?mobile=2',
      'fastloginfield': 'username',
      'cookietime': '2592000',
      'username': username,
      'password': password,
      'questionid': questionid,
      'answer': answer,
      'seccodehash': meta.seccodehash,
      'seccodemodid': 'member::logging',
      'seccodeverify': seccode,
    },
  );
  final doc = toDoc(html);
  if (isLoggedIn(doc) || RegExp('欢迎您回来|登录成功|succeedhandle_login').hasMatch(html)) {
    _capture(doc, html);
    return const SubmitResult(ok: true, message: '登入成功');
  }
  return SubmitResult(
    ok: false,
    message: noticeMessage(doc) ?? _cleanError(html) ?? '登入失敗，請確認帳號密碼與驗證碼',
  );
}

Future<SessionUser?> checkSession() async {
  final user = parseHeaderUser(await _page('forum.php'));
  return user.loggedIn ? user : null;
}

Future<void> logout() async {
  await _ensureFormhash();
  try {
    await Api.instance.get('member.php?mod=logging&action=logout&formhash=$_formhash');
  } on DiscuzException {
    // 就算伺服器端沒清成功，本地還是要能登出
  }
  _formhash = null;
  await Api.instance.clearCookies();
}

String _qs(Map<String, String> q) =>
    q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
