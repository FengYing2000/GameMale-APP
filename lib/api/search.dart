import 'package:html/dom.dart' as dom;

import 'discuz.dart' as discuz;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 搜尋。帖子有手機版；日誌／相簿／群組／使用者都沒有，
/// 靠 Api.get 自動跟進「無手機頁面」提示拿到桌面模板再解析。
Future<SearchResult> search(
  String keyword, {
  SearchScope scope = SearchScope.forum,
  int page = 1,
  int fid = 0,
  AdvancedSearch? advanced,
}) async {
  final hash = discuz.formhash;

  // 使用者搜尋其實是「查找好友」，走 home.php 而且參數叫 username
  final q = <String, String>{
    'mod': scope == SearchScope.user ? 'spacecp' : scope.mod,
    if (scope == SearchScope.user) 'ac': 'search',
    if (scope == SearchScope.user) 'username': keyword else 'srchtxt': keyword,
    'formhash': hash ?? '',
    'searchsubmit': 'yes',
    if (scope == SearchScope.forum &&
        fid > 0 &&
        (advanced?.forums.isEmpty ?? true))
      'srchfid[]': '$fid',
    // 高級搜索只有帖子搜尋吃得下
    if (scope == SearchScope.forum && advanced != null) ...advanced.toParams(),
  };
  if (page > 1) q['page'] = '$page';

  final parts = [
    for (final e in q.entries)
      '${e.key}=${Uri.encodeQueryComponent(e.value)}',
    // special[] 與 srchfid[] 都是陣列，同一個名字要重複出現，Map 帶不過去
    if (scope == SearchScope.forum && advanced != null) ...[
      for (final s in advanced.special) 'special%5B%5D=$s',
      // 高級搜索指定的版塊，會蓋掉「本版」那個 fid
      for (final f in advanced.forums) 'srchfid%5B%5D=$f',
    ],
  ];

  final base = scope == SearchScope.user ? 'home.php' : 'search.php';
  final url = '$base?${parts.join('&')}';
  final html = await Api.instance.get(url);
  final doc = toDoc(html);

  if (isLoginWall(doc)) {
    return const SearchResult(message: '需要先登入才能搜尋');
  }

  final hits = switch (scope) {
    SearchScope.forum => _parseForumHits(doc),
    SearchScope.blog => _parseBlogHits(doc),
    SearchScope.album => _parseAlbumHits(doc),
    SearchScope.group => _parseGroupHits(doc),
    SearchScope.user => _parseUserHits(doc),
  };

  return SearchResult(
    hits: hits,
    summary: txt(doc.querySelector('.sttl h2') ?? doc.querySelector('.thread_tit')),
    pager: parsePager(doc, current: page),
    message: hits.isEmpty ? (noticeMessage(doc) ?? '找不到符合的內容') : null,
  );
}

/// 帖子搜尋有三種版型：手機搜尋頁的 .searchList、
/// 一般主題列表的 .threadlist、桌面搜尋頁的 .slst
List<SearchHit> _parseForumHits(dom.Document doc) {
  final search = <SearchHit>[];
  for (final li in doc.querySelectorAll('.searchList li')) {
    final a = li.querySelector('a[href*="mod=viewthread"]');
    if (a == null) continue;
    final tid = paramInt(attr(a, 'href'), 'tid');
    if (tid == null) continue;
    search.add(SearchHit(title: txt(a), tid: tid));
  }
  if (search.isNotEmpty) return search;

  final mobile = discuz.parseThreadList(doc);
  if (mobile.isNotEmpty) {
    return [
      for (final t in mobile)
        SearchHit(
          title: t.title,
          subtitle: [t.author, t.date].where((s) => s.isNotEmpty).join(' · '),
          image: t.avatar,
          tid: t.tid,
          uid: t.uid,
        ),
    ];
  }

  final out = <SearchHit>[];
  for (final li in doc.querySelectorAll('.slst li')) {
    final a = li.querySelector('h3 a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final tid = paramInt(href, 'tid') ??
        int.tryParse(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1) ?? '');
    if (tid == null) continue;
    out.add(SearchHit(
      title: txt(a),
      subtitle: _joinInfo(li),
      tid: tid,
      url: absolute(href),
    ));
  }
  return out;
}

/// 日誌：`blog-<uid>-<blogid>.html`
List<SearchHit> _parseBlogHits(dom.Document doc) {
  final out = <SearchHit>[];
  for (final li in doc.querySelectorAll('.slst li')) {
    final a = li.querySelector('h3 a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final m = RegExp(r'blog-(\d+)-(\d+)').firstMatch(href);
    out.add(SearchHit(
      title: txt(a),
      subtitle: _joinInfo(li),
      uid: m == null ? null : int.tryParse(m.group(1)!),
      url: absolute(href),
    ));
  }
  return out;
}

/// 相簿：有封面圖
List<SearchHit> _parseAlbumHits(dom.Document doc) {
  final out = <SearchHit>[];
  for (final li in doc.querySelectorAll('.slst li')) {
    final a = li.querySelector('.ptm a') ?? li.querySelector('a');
    if (a == null) continue;
    final href = attr(a, 'href');
    out.add(SearchHit(
      title: txt(a),
      image: absolute(attr(li.querySelector('img'), 'src')),
      uid: paramInt(href, 'uid'),
      url: absolute(href),
    ));
  }
  return out;
}

/// 群組：`group-<fid>-1.html`
List<SearchHit> _parseGroupHits(dom.Document doc) {
  final out = <SearchHit>[];
  for (final dl in doc.querySelectorAll('.slst dl')) {
    final a = dl.querySelector('dt a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final fid = int.tryParse(RegExp(r'group-(\d+)').firstMatch(href)?.group(1) ?? '') ??
        paramInt(href, 'fid');
    out.add(SearchHit(
      title: txt(a),
      subtitle: dl.querySelectorAll('dd').map(txt).where((s) => s.isNotEmpty).join(' · '),
      image: absolute(attr(dl.querySelector('img'), 'src')),
      fid: fid,
      url: absolute(href),
    ));
  }
  return out;
}

/// 使用者：查找好友的 .buddy 清單
List<SearchHit> _parseUserHits(dom.Document doc) {
  final out = <SearchHit>[];
  for (final li in doc.querySelectorAll('.buddy li')) {
    final a = li.querySelector('h4 a') ?? li.querySelector('a');
    if (a == null) continue;
    final href = attr(a, 'href');
    final uid = int.tryParse(
            RegExp(r'space-uid-(\d+)').firstMatch(href)?.group(1) ?? '') ??
        paramInt(href, 'uid');
    if (uid == null) continue;
    out.add(SearchHit(
      title: txt(a),
      subtitle: txt(li.querySelector('.maxh')),
      image: avatarUrl(uid),
      uid: uid,
    ));
  }
  return out;
}

String _joinInfo(dom.Element li) => li
    .querySelectorAll('p')
    .map(txt)
    .where((s) => s.isNotEmpty)
    .take(2)
    .join(' · ');
