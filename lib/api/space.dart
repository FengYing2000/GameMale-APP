import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 個人空間。這些子頁在這站**只有桌面模板**：帶 mobile=2 一律回「無手機頁面」，
/// 所以整支檔案都走 desktop:true。
Future<SpaceData> fetchSpace(int uid, SpaceTab tab, {int page = 1}) async {
  final q = StringBuffer('home.php?mod=space&uid=$uid&do=${tab.action}');
  if (tab.view.isNotEmpty) q.write('&view=${tab.view}');
  if (page > 1) q.write('&page=$page');

  final html = await Api.instance.get(q.toString(), desktop: true);
  final doc = toDoc(html);

  if (isLoginWall(doc) || isRedirectToLogin(doc, html)) {
    return SpaceData(tab: tab, message: '要先登入才看得到${tab.label}', needsLogin: true);
  }

  // 空間可以設成只給好友或只給自己看
  final privacy = privacyMessage(doc);
  if (privacy != null) {
    return SpaceData(tab: tab, message: privacy, restricted: true);
  }

  return parseSpace(doc, tab);
}

/// 純解析，測試直接餵 fixture 用
SpaceData parseSpace(dom.Document doc, SpaceTab tab) {
  final items = switch (tab) {
    SpaceTab.home => _home(doc),
    SpaceTab.doing => _doing(doc),
    SpaceTab.blog => _blog(doc),
    SpaceTab.album => _album(doc),
    SpaceTab.thread => _thread(doc),
    SpaceTab.wall => _wall(doc),
    SpaceTab.friend => _friend(doc),
  };

  // 空白有兩種：真的沒東西，跟被主人鎖起來。後者論壇會給一段提示
  final notice = noticeMessage(doc);
  return SpaceData(
    tab: tab,
    owner: _owner(doc),
    items: items,
    pager: parsePager(doc),
    formhash: attr(doc.querySelector('input[name="formhash"]'), 'value'),
    message: items.isEmpty ? (notice ?? '沒有${tab.label}') : null,
  );
}

/// 只有首頁有 #pcd 側欄，其他子頁的主人名字只能從 `<title>` 取：「cdcai的记录-GameMale」
String _owner(dom.Document doc) {
  final side = txt(doc.querySelector('#pcd h2'));
  if (side.isNotEmpty) return side;
  final title = txt(doc.querySelector('title'));
  return RegExp(r'^(.*?)的').firstMatch(title)?.group(1) ?? '';
}

/// 空間首頁：把首頁那幾個區塊（最近訪客／記錄／主題／好友）拉平成一份摘要
List<SpaceItem> _home(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final block in doc.querySelectorAll('.block')) {
    final title = txt(block.querySelector('.blocktitle'));
    final content = block.querySelector('.dxb_bc');
    if (content == null || title.isEmpty) continue;
    if (title.contains('头像')) continue;

    final links = <SpaceItem>[];
    for (final li in content.querySelectorAll('li')) {
      final a = li.querySelector('a');
      final em = li.querySelector('em');
      // 「个人资料」那塊是 <em>標籤</em>值，不補空白會黏成「网名昵称风」
      final label = em == null
          ? txt(li)
          : '${txt(em)}  ${txt(li).replaceFirst(txt(em), '').trim()}'.trim();
      if (label.isEmpty) continue;
      links.add(SpaceItem(
        title: label,
        url: a == null ? '' : absolute(attr(a, 'href')),
        uid: a == null ? null : _uidOf(attr(a, 'href')),
        tid: a == null ? null : _tidOf(attr(a, 'href')),
        image: absolute(attr(li.querySelector('img'), 'src')),
      ));
    }
    if (links.isEmpty) continue;
    out.add(SpaceItem(title: title, children: links));
  }
  return out;
}

/// 記錄：`dl` 裡有正文、底下 `dd.cmt li` 是回覆
List<SpaceItem> _doing(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final dl in doc.querySelectorAll('.xld dl')) {
    final body = dl.querySelector('dd.ptm span');
    if (body == null) continue;
    final who = dl.querySelector('dd.ptm a');
    final time = dl.querySelector('dd.ptn span[title]');
    out.add(SpaceItem(
      title: txt(body),
      author: txt(who),
      uid: _uidOf(attr(who, 'href')),
      avatar: absolute(attr(dl.querySelector('dd.avt img'), 'src')),
      date: attr(time, 'title').isEmpty ? txt(time) : attr(time, 'title'),
      children: [
        for (final li in dl.querySelectorAll('dd.cmt li'))
          SpaceItem(
            author: txt(li.querySelector('a.lit')),
            uid: _uidOf(attr(li.querySelector('a.lit'), 'href')),
            title: txt(li)
                .replaceFirst(txt(li.querySelector('a.lit')), '')
                .replaceFirst(':', '')
                .replaceFirst('回复', '')
                .trim(),
          ),
      ],
    ));
  }
  return out;
}

/// 日誌：`dt a` 標題、`dd.cl` 摘要（可能有縮圖）、`dd.xg1` 閱讀／評論數
List<SpaceItem> _blog(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final dl in doc.querySelectorAll('.xld dl')) {
    final a = dl.querySelector('dt a');
    if (a == null) continue;
    // 標題是空的（例如整篇只有一張圖）就跳過，列出來也點不出東西
    if (txt(a).isEmpty) continue;
    final excerpt = dl.querySelector('dd.cl');
    out.add(SpaceItem(
      title: txt(a),
      url: absolute(attr(a, 'href')),
      author: txt(dl.querySelector('dd:not(.m) a[href*="space-uid"]')),
      uid: _uidOf(attr(dl.querySelector('dd:not(.m) a[href*="space-uid"]'), 'href')),
      avatar: absolute(attr(dl.querySelector('.avt img'), 'src')),
      date: txt(dl.querySelector('dd span.xg1')),
      body: txt(excerpt),
      image: absolute(attr(excerpt?.querySelector('img'), 'src')),
      meta: txt(dl.querySelector('dd.xg1')),
    ));
  }
  return out;
}

/// 相冊：封面圖 + `(張數)`
List<SpaceItem> _album(dom.Document doc) {
  final out = <SpaceItem>[];
  // 相冊清單是 ul.ml.mla
  final grid = doc.querySelectorAll('.mla li');
  for (final li in grid.isNotEmpty ? grid : doc.querySelectorAll('.ml li')) {
    final a = li.querySelector('p a') ?? li.querySelector('a');
    if (a == null) continue;
    final href = attr(a, 'href');
    out.add(SpaceItem(
      title: txt(a),
      url: absolute(href),
      image: absolute(attr(li.querySelector('img'), 'src')),
      meta: txt(li.querySelector('p.ptn')).replaceFirst(txt(a), '').trim(),
      albumId: paramInt(href, 'id'),
      uid: _uidOf(href),
      // 沒公開的相冊封面會被換成 nopublish.gif
      locked: attr(li.querySelector('img'), 'src').contains('nopublish'),
    ));
  }
  return out;
}

/// 主題：桌面版是表格，`th a` 標題、`td.frm` 版塊、`td.num` 回覆／查看
List<SpaceItem> _thread(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final tr in doc.querySelectorAll('.tl tr')) {
    final a = tr.querySelector('th a');
    if (a == null) continue;
    final tid = _tidOf(attr(a, 'href'));
    if (tid == null) continue;
    final num = tr.querySelector('td.num');
    final forum = tr
        .querySelectorAll('td')
        .where((td) => td.classes.isEmpty && td.querySelector('a') != null)
        .firstOrNull;
    out.add(SpaceItem(
      title: txt(a),
      tid: tid,
      url: absolute(attr(a, 'href')),
      fid: paramInt(attr(forum?.querySelector('a'), 'href'), 'fid') ??
          int.tryParse(RegExp(r'forum-(\d+)')
                  .firstMatch(attr(forum?.querySelector('a'), 'href'))
                  ?.group(1) ??
              ''),
      meta: [
        txt(forum),
        if (num != null) '${txt(num.querySelector('a'))} / ${txt(num.querySelector('em'))}',
      ].where((s) => s.trim().isNotEmpty).join(' · '),
      author: txt(tr.querySelector('td.by cite a')),
      date: txt(tr.querySelector('td.by em span')),
    ));
  }
  return out;
}

/// 留言板：`#comment_ul dl`
List<SpaceItem> _wall(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final dl in doc.querySelectorAll('#comment_ul dl')) {
    final who = dl.querySelector('dt a');
    // 內文那個 dd 沒有 class，跟頭像／標題那兩個區分得開
    dom.Element? body;
    for (final dd in dl.querySelectorAll('dd')) {
      if (dd.classes.isEmpty && attr(dd, 'id').startsWith('comment_')) body = dd;
    }
    if (who == null && body == null) continue;
    out.add(SpaceItem(
      title: txt(body),
      author: txt(who),
      uid: _uidOf(attr(who, 'href')),
      avatar: absolute(attr(dl.querySelector('dd.avt img'), 'src')),
      date: txt(dl.querySelector('dt span.xg1')),
    ));
  }
  return out;
}

/// 好友：`ul.buddy li`
List<SpaceItem> _friend(dom.Document doc) {
  final out = <SpaceItem>[];
  for (final li in doc.querySelectorAll('.buddy li')) {
    final a = li.querySelector('h4 a') ?? li.querySelector('a');
    if (a == null) continue;
    final uid = _uidOf(attr(a, 'href'));
    if (uid == null) continue;
    out.add(SpaceItem(
      title: txt(a),
      uid: uid,
      avatar: avatarUrl(uid),
      meta: txt(li.querySelector('.maxh')),
    ));
  }
  return out;
}

/// 留言板留言。走桌面端點，回的是 ajax 片段
Future<SubmitResult> postWall(int uid, String message, String formhash) async {
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=comment&commentsubmit=yes&handlekey=qcwall_$uid&inajax=1',
    {
      'formhash': formhash,
      'message': message,
      'id': '$uid',
      'idtype': 'uid',
      'commentsubmit': 'true',
      'quickcomment': 'true',
      'handlekey': 'qcwall_$uid',
    },
    desktop: true,
  );
  return submitResult(html, '留言');
}

int? _uidOf(String href) =>
    int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(href)?.group(1) ?? '') ??
    paramInt(href, 'uid');

int? _tidOf(String href) =>
    int.tryParse(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1) ?? '') ??
    paramInt(href, 'tid');


/// 相冊內頁。縮圖網址後面接了 `.thumb.jpg`，去掉就是原圖
Future<AlbumData> fetchAlbum(int uid, int albumId, {int page = 1}) async {
  final q = 'home.php?mod=space&uid=$uid&do=album&id=$albumId'
      '${page > 1 ? '&page=$page' : ''}';
  final doc = toDoc(await Api.instance.get(q, desktop: true));
  return parseAlbum(doc);
}

AlbumData parseAlbum(dom.Document doc) {
  final photos = <AlbumPhoto>[];
  // 照片格是 ul.ml.mlp；只寫 .ml 會連側欄那排小圖一起抓進來
  final grid = doc.querySelectorAll('.mlp li');
  for (final li in grid.isNotEmpty ? grid : doc.querySelectorAll('.ml li')) {
    final img = li.querySelector('img');
    if (img == null) continue;
    final thumb = absolute(attr(img, 'src'));
    if (thumb.isEmpty) continue;
    photos.add(AlbumPhoto(
      thumb: thumb,
      full: thumb.replaceFirst(RegExp(r'\.thumb\.jpg$'), ''),
      picid: paramInt(attr(li.querySelector('a'), 'href'), 'picid'),
    ));
  }
  final head = txt(doc.querySelector('.tbmu'));
  return AlbumData(
    title: RegExp(r'^(.*?)\s*-').firstMatch(txt(doc.querySelector('title')))?.group(1) ??
        txt(doc.querySelector('title')),
    count: RegExp(r'共\s*\d+\s*张图片').firstMatch(head)?.group(0) ?? '',
    photos: photos,
    pager: parsePager(doc),
    message: photos.isEmpty ? (noticeMessage(doc) ?? '這本相冊看不到內容') : null,
  );
}

/// 日誌內頁
Future<BlogData> fetchBlog(int uid, int blogId) async {
  final doc = toDoc(
      await Api.instance.get('blog-$uid-$blogId.html', desktop: true));
  return parseBlog(doc);
}

BlogData parseBlog(dom.Document doc) {
  final article = doc.querySelector('#blog_article');
  if (article == null) {
    return BlogData(
        message: privacyMessage(doc) ?? noticeMessage(doc) ?? '看不到這篇日誌');
  }

  // 表態：`#click_div td a` 裡有計數 <em>、圖示 <img> 與名稱
  final reactions = <BlogReaction>[];
  for (final a in doc.querySelectorAll('#click_div td a')) {
    final name = txt(a).replaceAll(RegExp(r'^\d+\s*'), '').trim();
    if (name.isEmpty) continue;
    reactions.add(BlogReaction(
      name: name,
      count: int.tryParse(txt(a.querySelector('em'))) ?? 0,
      icon: absolute(attr(a.querySelector('img'), 'src')),
      url: absolute(attr(a, 'href')),
    ));
  }

  final reactedBy = <SpaceItem>[];
  for (final li in doc.querySelectorAll('#trace_ul li')) {
    final link = li.querySelector('p a') ?? li.querySelector('a');
    if (link == null) continue;
    final uid = _uidOf(attr(link, 'href'));
    reactedBy.add(SpaceItem(
      title: txt(link),
      uid: uid,
      avatar: uid == null ? '' : avatarUrl(uid),
      // 頭像的 title 就是他按了哪個表態
      meta: attr(li.querySelector('.avt a'), 'title'),
    ));
  }

  final comments = <BlogComment>[];
  for (final dl in doc.querySelectorAll('#comment_ul dl')) {
    final who = dl.querySelector('dt a[href*="space-uid"]');
    dom.Element? body;
    for (final dd in dl.querySelectorAll('dd')) {
      if (attr(dd, 'id').startsWith('comment_') && dd.classes.isEmpty) body = dd;
    }
    if (body == null && who == null) continue;
    final quote = body?.querySelector('.quote');
    final quoteText = txt(quote);
    comments.add(BlogComment(
      author: txt(who),
      uid: _uidOf(attr(who, 'href')),
      avatar: absolute(attr(dl.querySelector('dd.avt img'), 'src')),
      date: txt(dl.querySelector('dt span.xg1')),
      text: quoteText.isEmpty
          ? txt(body)
          : txt(body).replaceFirst(quoteText, '').trim(),
      quote: quoteText,
    ));
  }

  final others = <SpaceItem>[];
  for (final li in doc.querySelectorAll('.ct_vw_sd li')) {
    final a = li.querySelector('a[href*="blog-"]');
    if (a == null) continue;
    others.add(SpaceItem(title: txt(a), url: absolute(attr(a, 'href'))));
  }

  return BlogData(
    title: txt(doc.querySelector('.vw h1.ph') ?? doc.querySelector('h1.ph')),
    author: txt(doc.querySelector('#pcd h2')),
    meta: txt(doc.querySelector('.vw .h p.xg2')),
    html: sanitizeContent(article),
    reactions: reactions,
    reactedBy: reactedBy,
    reactedCount: txt(doc.querySelector('#click_div ~ h3')).isEmpty
        ? txt(doc.querySelector('h3.mbm'))
        : txt(doc.querySelector('#click_div ~ h3')),
    comments: comments,
    otherPosts: others,
    formhash: attr(doc.querySelector('input[name="formhash"]'), 'value'),
  );
}

/// 日誌留言。跟留言板同一支端點，只是 idtype 換成 blogid
Future<SubmitResult> postBlogComment(
  int blogId,
  String message,
  String formhash,
) async {
  final html = await Api.instance.post(
    'home.php?mod=spacecp&ac=comment&commentsubmit=yes'
    '&handlekey=commentbloghk_$blogId&inajax=1',
    {
      'formhash': formhash,
      'message': message,
      'id': '$blogId',
      'idtype': 'blogid',
      'commentsubmit': 'true',
      'quickcomment': 'true',
      'handlekey': 'commentbloghk_$blogId',
    },
    desktop: true,
  );
  return submitResult(html, '留言');
}


/// 日誌廣場。跟記錄廣場一樣有三種視角，好友／我的都要登入
Future<BlogListPage> fetchBlogList(
  String view, {
  int page = 1,
  int catid = 0,
}) async {
  final q = StringBuffer('home.php?mod=space&do=blog&view=$view');
  if (catid > 0) q.write('&catid=$catid');
  if (page > 1) q.write('&page=$page');

  final html = await Api.instance.get(q.toString(), desktop: true);
  final doc = toDoc(html);

  if (isLoginWall(doc) || isRedirectToLogin(doc, html)) {
    return const BlogListPage(message: '要先登入才看得到', needsLogin: true);
  }

  final cats = <BlogCategory>[];
  for (final a in doc.querySelectorAll('a[href*="catid="]')) {
    final id = paramInt(attr(a, 'href'), 'catid');
    final name = txt(a);
    if (id == null || name.isEmpty) continue;
    if (cats.any((c) => c.catid == id)) continue;
    cats.add(BlogCategory(catid: id, name: name));
  }

  final items = _blog(doc);
  return BlogListPage(
    items: items,
    categories: cats,
    pager: parsePager(doc),
    message: items.isEmpty ? (noticeMessage(doc) ?? '這裡沒有日誌') : null,
  );
}

/// 對日誌表態（震驚／感謝／關心／加油／有愛）。
/// 連結裡已經帶好 clickid 與 hash，直接 GET 就是送出
Future<SubmitResult> clickBlogReaction(String url) async {
  if (url.isEmpty) return const SubmitResult(ok: false, message: '這個表態沒有連結');
  var path = url.replaceAll('&amp;', '&');
  if (path.startsWith(kOrigin)) path = path.substring(kOrigin.length);
  final html = await Api.instance
      .get('${path.replaceFirst(RegExp(r'^/'), '')}&inajax=1', desktop: true);
  return submitResult(html, '表態');
}
