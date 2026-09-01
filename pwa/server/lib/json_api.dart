import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';

/// 把 gm_api 的模型轉成前端吃的 JSON。
///
/// 解析都在 gm_api 裡做完了，這裡只負責攤平成 Map——前端不必再認識
/// 論壇的 HTML，拿到的就是結構化資料。

/// 論壇的圖片幾乎都要帶登入 cookie 才拿得到（附件、頭像尤其明顯）。
/// 瀏覽器沒有那份 cookie，也不該有，所以圖片一律改走自己的代理。
String proxyImage(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('data:')) return url;
  return '/api/img?u=${Uri.encodeComponent(absoluteUrl(url))}';
}

/// 論壇給的網址有絕對、相對、以及 `//` 開頭三種，統一補成絕對網址
String absoluteUrl(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return '$kOrigin$url';
  return '$kOrigin/$url';
}

/// 把貼文 HTML 裡的圖片換成走代理，連結補成絕對網址。
///
/// 前端直接把這段 HTML 塞進頁面，所以順手把論壇的行內樣式留著
/// （字體大小、顏色那些是使用者自己排的版），但圖片一定要改寫，
/// 不然全部載不出來。
String rewritePostHtml(String html) {
  if (html.isEmpty) return html;
  var out = html;

  // src / file / data-original 都可能是圖片來源（論壇有延遲載入）
  for (final attr in ['src', 'file', 'data-original', 'zoomfile']) {
    out = out.replaceAllMapped(
      RegExp('$attr="([^"]*)"', caseSensitive: false),
      (m) {
        final v = m[1] ?? '';
        if (v.isEmpty || v.startsWith('data:')) return m[0]!;
        return 'src="${proxyImage(v)}"';
      },
    );
  }

  // 站內連結補成絕對網址，讓前端能判斷要不要攔下來自己導頁
  out = out.replaceAllMapped(
    RegExp(r'href="(?!https?://|#|javascript:|mailto:)([^"]*)"'),
    (m) => 'href="${absoluteUrl(m[1] ?? '')}"',
  );

  return out;
}

Map<String, dynamic> pageInfoJson(PageInfo p) => {
      'page': p.page,
      'total': p.total,
      'hasNext': p.hasNext,
      'hasPrev': p.hasPrev,
      'numbered': p.numbered,
    };

Map<String, dynamic> forumItemJson(ForumItem f) => {
      'fid': f.fid,
      'name': f.name,
      'icon': proxyImage(f.icon),
      'threads': f.threads,
      'posts': f.posts,
      'desc': f.desc,
      'descHtml': rewritePostHtml(f.descHtml),
      'moderators': f.moderators,
      'subforums': [
        for (final s in f.subforums)
          {'fid': s.fid, 'name': s.name, 'icon': proxyImage(s.icon)}
      ],
    };

Map<String, dynamic> indexJson(IndexData d) => {
      'user': {
        'name': d.user.name,
        'uid': d.user.uid,
        'avatar': proxyImage(d.user.avatar),
        'loggedIn': d.user.loggedIn,
      },
      'sign': d.sign == null
          ? null
          : {
              'signed': d.sign!.signed,
              'label': d.sign!.label,
              'title': d.sign!.title,
              'exp': d.sign!.exp,
              'expMax': d.sign!.expMax,
              'percent': d.sign!.percent,
              'maxed': d.sign!.maxed,
            },
      'groups': [
        for (final g in d.groups)
          {
            'name': g.name,
            'forums': [for (final f in g.forums) forumItemJson(f)]
          }
      ],
    };

Map<String, dynamic> threadItemJson(ThreadItem t) => {
      'tid': t.tid,
      'title': t.title,
      'type': t.type,
      'author': t.author,
      'uid': t.uid,
      'avatar': proxyImage(t.avatar),
      'date': t.date,
      'views': t.views,
      'replies': t.replies,
      'digest': t.digest,
      'favid': t.favid,
      'forumName': t.forumName,
      'fid': t.fid,
      'myReply': t.myReply,
      'myPid': t.myPid,
    };

Map<String, dynamic> forumJson(ForumData f) => {
      'fid': f.fid,
      'name': f.name,
      'meta': f.meta,
      'message': f.message,
      'requiresLogin': f.requiresLogin,
      'subforums': [
        for (final s in f.subforums)
          {'fid': s.fid, 'name': s.name, 'icon': proxyImage(s.icon)}
      ],
      'types': [
        for (final t in f.types)
          {'typeid': t.typeid, 'name': t.name, 'count': t.count}
      ],
      'tabs': [
        for (final t in f.tabs)
          {
            'name': t.name,
            'cur': t.cur,
            'filter': t.filter,
            'orderby': t.orderby,
            'digest': t.digest,
          }
      ],
      'list': [for (final t in f.list) threadItemJson(t)],
      'pager': pageInfoJson(f.pager),
    };

Map<String, dynamic> postJson(PostItem p) => {
      'pid': p.pid,
      'floor': p.floor,
      'author': p.author,
      'uid': p.uid,
      'avatar': proxyImage(p.avatar),
      'time': p.time,
      'html': rewritePostHtml(p.html),
      'signature': rewritePostHtml(p.signature),
      'quoteHref': p.quoteHref,
      'comments': [
        for (final c in p.comments)
          {
            'name': c.name,
            'uid': c.uid,
            'avatar': proxyImage(c.avatar),
            'text': c.text,
          }
      ],
    };

Map<String, dynamic> threadJson(ThreadData t) => {
      'tid': t.tid,
      'fid': t.fid,
      'forumName': t.forumName,
      'title': t.title,
      'type': t.type,
      'requiresLogin': t.requiresLogin,
      'posts': [for (final p in t.posts) postJson(p)],
      'pager': pageInfoJson(t.pager),
      'poll': t.poll == null
          ? null
          : {
              'title': t.poll!.title,
              'info': t.poll!.info,
              'deadline': t.poll!.deadline,
              'multiple': t.poll!.multiple,
              'voted': t.poll!.voted,
              'votable': t.poll!.votable,
              'status': t.poll!.status,
              'options': [
                for (final o in t.poll!.options)
                  {
                    'id': o.id,
                    'text': o.text,
                    'votes': o.votes,
                    'percent': o.percent,
                  }
              ],
            },
    };

Map<String, dynamic> pmItemJson(PmItem p) => {
      'touid': p.touid,
      'name': p.name,
      'avatar': proxyImage(p.avatar),
      'last': p.last,
      'time': p.time,
      'unread': p.unread,
    };

Map<String, dynamic> pmChatJson(PmChat c) => {
      'touid': c.touid,
      'title': c.title,
      'pmid': c.pmid,
      'messages': [
        for (final m in c.messages)
          {
            'mine': m.mine,
            'avatar': proxyImage(m.avatar),
            'html': rewritePostHtml(m.html),
            'text': m.text,
            'time': m.time,
          }
      ],
    };

Map<String, dynamic> noticeItemJson(NoticeItem n) => {
      'id': n.id,
      'avatar': proxyImage(n.avatar),
      'uid': n.uid,
      'time': n.time,
      'text': n.text,
      'tid': n.tid,
    };
