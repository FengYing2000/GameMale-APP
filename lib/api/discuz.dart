import 'dart:typed_data';

import 'package:html/dom.dart' as dom;

import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 全站共用的 formhash，換頁時順手更新
String? _formhash;
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
      final desc = txt(li.querySelector('p'));
      forums.add(ForumItem(
        fid: paramInt(attr(a, 'href'), 'fid') ?? 0,
        name: name,
        icon: absolute(attr(li.querySelector('.f_icon img'), 'src')),
        threads: nums.isNotEmpty ? nums[0] : '',
        posts: attr(count?.querySelector('span[title]'), 'title').isNotEmpty
            ? attr(count?.querySelector('span[title]'), 'title')
            : (nums.length > 1 ? nums[1] : ''),
        desc: desc.length > 90 ? desc.substring(0, 90) : desc,
      ));
    }
    if (forums.isNotEmpty) {
      groups.add(ForumGroup(name: txt(head.querySelector('h2')), forums: forums));
    }
  }

  return IndexData(groups: groups, user: parseHeaderUser(doc), sign: parseSignWidget(doc));
}

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
  String filter = '',
  String orderby = '',
  int typeid = 0,
  bool digest = false,
}) async {
  final q = <String, String>{'mod': 'forumdisplay', 'fid': '$fid'};
  if (page > 1) q['page'] = '$page';
  if (filter.isNotEmpty) q['filter'] = filter;
  if (orderby.isNotEmpty) q['orderby'] = orderby;
  if (typeid > 0) {
    q['filter'] = 'typeid';
    q['typeid'] = '$typeid';
  }
  if (digest) q['digest'] = '1';

  final doc = await _page('forum.php?${_qs(q)}');
  return parseForumFromDoc(doc, fid);
}

ForumData parseForumFromDoc(dom.Document doc, int fid) {
  return ForumData(
    fid: fid,
    name: txt(doc.querySelector('header h1')).isNotEmpty
        ? txt(doc.querySelector('header h1'))
        : txt(doc.querySelector('.forumListHeader h3')),
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
    pager: parsePager(doc),
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
    final avatar = attr(li.querySelector('.h_avatar img'), 'src');
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
  final headAvatar = attr(attrBox?.querySelector('.h_avatar img'), 'src');
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
    final av = attr(tit?.querySelector('.h_avatar img'), 'src');
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

  return Poll(
    title: txt(box.querySelector('.pollTit h3')),
    info: txt(box.querySelector('.pollUser')),
    deadline: txt(box.querySelector('.pollTime')),
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
  return ListPage(list: parseThreadList(doc), pager: parsePager(doc));
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
  if (list.isNotEmpty) return ListPage(list: list, pager: parsePager(doc));

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
    pager: parsePager(doc),
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
    '请先登录|請先登錄|需要先登入|尚未登录|抱歉|不存在|已关闭|已關閉');

SubmitResult submitResult(String html, String what) => _submitResult(html, what);

SubmitResult _submitResult(String html, String what) {
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
  return SignResult(
    html: sanitizeContent(doc.querySelector('.container') ?? doc.body),
    signed: RegExp('已签到').hasMatch(doc.body?.text ?? ''),
  );
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
  NoticeTab('interactive', '', '坛友互动'),
  NoticeTab('system', '', '系统提醒'),
  NoticeTab('app', '', '应用提醒'),
];

const noticeTypes = <String, List<NoticeTab>>{
  'mypost': [
    NoticeTab('mypost', '', '全部'),
    NoticeTab('mypost', 'post', '帖子'),
    NoticeTab('mypost', 'pcomment', '点评'),
    NoticeTab('mypost', 'activity', '活动'),
    NoticeTab('mypost', 'reward', '悬赏'),
    NoticeTab('mypost', 'goods', '商品'),
    NoticeTab('mypost', 'at', '提到我的'),
  ],
  'interactive': [
    NoticeTab('interactive', '', '全部'),
    NoticeTab('interactive', 'poke', '打招呼'),
    NoticeTab('interactive', 'friend', '好友'),
    NoticeTab('interactive', 'wall', '留言'),
    NoticeTab('interactive', 'comment', '评论'),
    NoticeTab('interactive', 'click', '挺你'),
    NoticeTab('interactive', 'sharenotice', '分享'),
  ],
};

/// 通知頁沒有手機版，Discuz 會回桌面模板，結構是 .nts > dl 而不是 li。
/// 內文連結指向 mod=redirect，主題 id 放在 ptid。
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
    final av = attr(dl.querySelector('.avt img'), 'src');
    items.add(NoticeItem(
      id: attr(dl, 'notice'),
      avatar: av,
      uid: paramInt(av, 'uid'),
      time: txt(dl.querySelector('dt span')),
      text: text,
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
  final doc = await _page('home.php?mod=space&do=pm');
  final items = <PmItem>[];
  for (final li in doc.querySelectorAll('.pmbox li')) {
    final a = li.querySelector('a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final touid = paramInt(href, 'touid');
    if (touid == null) continue;
    items.add(PmItem(
      touid: touid,
      name: txt(li.querySelector('.name')),
      last: txt(li.querySelector('.grey')),
      time: txt(li.querySelector('.time')),
      avatar: attr(li.querySelector('.avatar_img img'), 'src'),
      unread: digits(txt(li.querySelector('.num'))),
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
      avatar: attr(box.querySelector('.avat img'), 'src'),
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
    level: RegExp(r'Lvl\.\s*(\d+)').firstMatch(title)?.group(1) ?? '',
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
        medals.add(Medal(
          image: src,
          name: zh(attr(img, 'alt')),
          desc: plainText(attr(img, 'tip')),
        ));
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

/// node 是不是在 ancestor 底下
bool _within(dom.Element node, dom.Element ancestor) {
  for (var p = node.parent; p != null; p = p.parent) {
    if (identical(p, ancestor)) return true;
  }
  return false;
}

/// 加好友（論壇會回一個確認表單頁，成功與否看回應訊息）
Future<SubmitResult> addFriend(int uid) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=friend&op=add&uid=$uid&handlekey=a_friend_$uid&formhash=$_formhash');
  return _submitResult(html, '加好友');
}

/// 打招呼
Future<SubmitResult> poke(int uid) async {
  await _ensureFormhash();
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=poke&op=send&uid=$uid&pokesubmit=true&infloat=yes',
    {'formhash': _formhash ?? '', 'note': '', 'pokesubmit': 'true'},
  );
  return _submitResult(html, '打招呼');
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
  if (list.isNotEmpty) return ListPage(list: list, pager: parsePager(doc));

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
  return ListPage(list: seen.values.toList(), pager: parsePager(doc));
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

Future<SubmitResult> favoriteThread(int tid) async {
  await _ensureFormhash();
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&handlekey=favoritethread&formhash=$_formhash');
  return _submitResult(html, '收藏');
}

Future<SubmitResult> unfavorite(int favid) async {
  await _ensureFormhash();
  final html = await Api.instance
      .get('home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&formhash=$_formhash');
  return _submitResult(html, '取消收藏');
}


/* ─────────────── 積分變化（勳章觸發） ─────────────── */

/// 論壇會在頁面裡輸出權威對照，例如
/// creditnotice = '1|旅程|里,2|金币|枚,3|血液|滴,...'
/// 注意順序和積分頁上的排列不同，照畫面順序猜會標錯名稱。
List<({String name, String unit})> _creditNames = const [];

void _captureCreditNames(String html) {
  final m = RegExp(r"creditnotice\s*=\s*'([^']+)'").firstMatch(html);
  if (m == null) return;
  final out = <({String name, String unit})>[];
  for (final part in m.group(1)!.split(',')) {
    final f = part.split('|');
    if (f.length >= 3) out.add((name: f[1], unit: f[2]));
  }
  if (out.isNotEmpty) _creditNames = out;
}

/// 讀 `<cookiepre>_creditnotice`，解出這次操作得到的積分。
///
/// cookie 是「每項變化量」以 D 相連，最後接 uid。前 N 項對應上面那份名稱表，
/// 多出來的一項是總積分，論壇自己的 JS 也不顯示它。
Future<List<CreditChange>> consumeCreditNotice() async {
  final raw = await Api.instance.cookieEndingWith('_creditnotice');
  if (raw == null || raw.isEmpty || _creditNames.isEmpty) return const [];

  final parts = raw.split('D');
  if (parts.length < 2) return const [];
  final values = parts.sublist(0, parts.length - 1);   // 去掉結尾的 uid

  final out = <CreditChange>[];
  for (var i = 0; i < _creditNames.length && i < values.length; i++) {
    final v = int.tryParse(values[i]) ?? 0;
    if (v != 0) out.add(CreditChange(_creditNames[i].name, v, _creditNames[i].unit));
  }
  return out;
}

/* ─────────────── 記錄廣場 ─────────────── */

/// 只有 all 是公開的；we/me 需要帳號
const doingViews = <({String key, String name, bool needsLogin})>[
  (key: 'all', name: '隨便看看', needsLogin: false),
  (key: 'we', name: '我和好友', needsLogin: true),
  (key: 'me', name: '我的記錄', needsLogin: true),
];

/// 記錄沒有手機版，帶 forcemobile=1 拿桌面模板來解析
Future<DoingPage> fetchDoing({String view = 'all'}) async {
  final doc = await _page('home.php?mod=space&do=doing&view=$view&forcemobile=1');
  final items = <DoingItem>[];

  for (final dl in doc.querySelectorAll('.xld dl')) {
    final id = attr(dl, 'id');
    final doid = int.tryParse(RegExp(r'dl(\d+)$').firstMatch(id)?.group(1) ?? '');
    if (doid == null) continue;

    final body = dl.querySelector('.ptm');
    final link = body?.querySelector('a');
    final href = attr(link, 'href');
    items.add(DoingItem(
      doid: doid,
      uid: int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(href)?.group(1) ?? '') ??
          paramInt(href, 'uid'),
      name: txt(link),
      avatar: attr(dl.querySelector('.avt img'), 'src'),
      message: txt(body?.querySelector('span')),
      time: txt(dl.querySelector('.ptn .y')),
    ));
  }

  return DoingPage(
    items: items,
    formhash: attr(doc.querySelector('#mood_addform input[name="formhash"]'), 'value'),
  );
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
