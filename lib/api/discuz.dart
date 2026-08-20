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

Future<dom.Document> _page(String url) async {
  final html = await Api.instance.get(url);
  final doc = toDoc(html);
  _capture(doc, html);
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
  return SignInfo(
    signed: btn.classes.contains('signed'),
    label: txt(btn),
    title: attr(btn, 'title').trim(),
    exp: nums.isNotEmpty ? digits(nums[0]) : 0,
    expMax: nums.length > 1 ? digits(nums[1]) : 0,
    percent: pct == null ? 0 : (double.tryParse(pct.group(1)!) ?? 0),
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
    final a = li.querySelector('a.forumDisplayImgList') ??
        li.querySelector('a[href*="mod=viewthread"]');
    if (a == null) continue;
    final tid = paramInt(attr(a, 'href'), 'tid');
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
      html: sanitizeContent(body),
      signature: sanitizeContent(it.querySelector('.sign')),
      quoteHref: attr(it.querySelector('.replybtn input'), 'href'),
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
  );
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

SubmitResult _submitResult(String html, String what) {
  final doc = toDoc(html);
  final msg = noticeMessage(doc);
  final jump = attr(doc.querySelector('.jump_c a'), 'href');
  final ok = RegExp('succeed|非常感谢|发布成功|操作成功|成功').hasMatch(html) ||
      jump.contains('mod=viewthread');
  if (ok) return SubmitResult(ok: true, message: msg ?? '$what成功');
  return SubmitResult(ok: false, message: msg ?? '$what失敗，可能是權限不足或發文間隔限制');
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
  final text = txt(toDoc(html).body).isNotEmpty
      ? txt(toDoc(html).body)
      : html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
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

const noticeViews = <MapEntry<String, String>>[
  MapEntry('mypost', '我的帖子'),
  MapEntry('interactive', '坛友互动'),
  MapEntry('system', '系统通知'),
  MapEntry('manage', '管理'),
];

/// 通知頁沒有手機版，Discuz 會回桌面模板，結構是 .nts > dl 而不是 li。
/// 內文連結指向 mod=redirect，主題 id 放在 ptid。
Future<NoticeResult> fetchNotice({String view = 'mypost'}) async {
  final doc = await _page('home.php?mod=space&do=notice&view=$view&forcemobile=1');
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

Future<PmListResult> fetchPmList() async {
  final doc = await _page('home.php?mod=space&do=pm');
  final items = <PmItem>[];
  for (final li in doc.querySelectorAll('.pmbox li')) {
    final href = attr(li.querySelector('a'), 'href');
    final name = txt(li.querySelector('h4') ?? li.querySelector('a'));
    if (name.isEmpty) continue;
    items.add(PmItem(
      touid: paramInt(href, 'touid') ?? paramInt(href, 'uid'),
      name: name,
      last: txt(li.querySelector('p')),
      time: txt(li.querySelector('.time') ?? li.querySelector('em')),
      avatar: attr(li.querySelector('img'), 'src'),
    ));
  }
  return PmListResult(items: items, message: items.isEmpty ? '目前沒有私訊' : null);
}

Future<List<PmMessage>> fetchPmChat(int touid) async {
  final doc = await _page('home.php?mod=space&do=pm&subop=view&touid=$touid');
  final out = <PmMessage>[];
  for (final li in doc.querySelectorAll('.pmlist li, .pm_list li, .pmbox li')) {
    final t = txt(li);
    if (t.isNotEmpty) out.add(PmMessage(html: sanitizeContent(li), text: t));
  }
  return out;
}

Future<SubmitResult> sendPm(int touid, String message) async {
  await _ensureFormhash();
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=pm&op=send&pmsubmit=yes&infloat=yes',
    {
      'formhash': _formhash ?? '',
      'message': message,
      'pmsubmit': 'true',
      'touid': '$touid',
    },
  );
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

Future<ProfileData> fetchProfile(int uid) async {
  final doc = await _page('home.php?mod=space&uid=$uid');
  return ProfileData(
    uid: uid,
    name: txt(doc.querySelector('header h1') ?? doc.querySelector('.user_avatar h2')),
    avatar: avatarUrl(uid, size: 'big'),
    html: sanitizeContent(doc.querySelector('.container') ?? doc.body),
  );
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

Future<ListPage> _myList(int uid, String doType, int page) async {
  final q = <String, String>{'mod': 'space', 'uid': '$uid', 'do': doType, 'view': 'me'};
  if (doType == 'favorite') q['type'] = 'thread';
  if (page > 1) q['page'] = '$page';
  final doc = await _page('home.php?${_qs(q)}');

  final list = doType == 'favorite' ? parseFavList(doc) : parseThreadList(doc);
  if (list.isNotEmpty) return ListPage(list: list, pager: parsePager(doc));

  final seen = <int, ThreadItem>{};
  for (final a in doc.querySelectorAll('a[href*="mod=viewthread"], a[href*="/thread-"]')) {
    final href = attr(a, 'href');
    final tid = paramInt(href, 'tid') ??
        int.tryParse(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1) ?? '');
    final title = txt(a);
    if (tid != null && title.isNotEmpty) {
      seen.putIfAbsent(tid, () => ThreadItem(tid: tid, title: title));
    }
  }
  return ListPage(list: seen.values.toList(), pager: parsePager(doc));
}

Future<ListPage> fetchFavorites(int uid, {int page = 1}) => _myList(uid, 'favorite', page);
Future<ListPage> fetchMyThreads(int uid, {int page = 1}) => _myList(uid, 'thread', page);
Future<ListPage> fetchMyReplies(int uid, {int page = 1}) => _myList(uid, 'reply', page);

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
