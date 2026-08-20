import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'http.dart';
import 'models.dart';

dom.Document toDoc(String html) => html_parser.parse(html);

/// 取文字並把連續空白（含 &nbsp;）收成單一空格
String txt(dom.Node? node) {
  if (node == null) return '';
  final s = node is dom.Element ? node.text : (node.text ?? '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String attr(dom.Element? el, String name) => el?.attributes[name] ?? '';

/// 從網址取出查詢參數，例如 tid / fid / uid
String? param(String? href, String key) {
  if (href == null || href.isEmpty) return null;
  final m = RegExp('[?&]$key=([^&#]+)').firstMatch(href.replaceAll('&amp;', '&'));
  return m == null ? null : Uri.decodeComponent(m.group(1)!);
}

int? paramInt(String? href, String key) {
  final v = param(href, key);
  return v == null ? null : int.tryParse(v);
}

int digits(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0;

String? formhashOf(dom.Document doc, [String? html]) {
  final el = doc.querySelector('input[name="formhash"]');
  final v = attr(el, 'value');
  if (v.isNotEmpty) return v;
  final m = RegExp('formhash=([a-f0-9]{8})', caseSensitive: false)
      .firstMatch(html ?? doc.outerHtml);
  return m?.group(1);
}

/// Discuz 未登入時頁面沒有登出連結，用這個判斷比去猜 cookie 可靠
bool isLoggedIn(dom.Document doc) =>
    doc.querySelector('a[href*="action=logout"]') != null ||
    doc.querySelector('a[href*="mycenter=1"]') != null;

String? noticeMessage(dom.Document doc) {
  final el = doc.querySelector(
      '.alert_error, .alert_info, .alert_right, .del_tips, #messagetext p');
  final t = txt(el);
  return t.isEmpty ? null : t;
}

const _strip = ['script', 'style', 'noscript', 'iframe', 'object', 'embed', 'form', 'link', 'meta'];

/// 把 Discuz 的帖子 HTML 整理成能安全交給 flutter_widget_from_html 的樣子。
///
/// - 拿掉腳本與事件屬性
/// - 還原延遲載入圖（真正的網址在 file / zoomfile）
/// - 所有網址絕對化，站內連結標上 data-inapp 給 App 內導航接手
/// - spoiler 折疊區塊轉成 data-spoiler，由 PostBody 畫成可展開的區塊
String sanitizeContent(dom.Element? el) {
  if (el == null) return '';
  final node = el.clone(true);

  for (final tag in _strip) {
    for (final n in node.querySelectorAll(tag).toList()) {
      n.remove();
    }
  }

  for (final n in node.querySelectorAll('*').toList()) {
    final bad = n.attributes.keys
        .where((k) => k.toString().toLowerCase().startsWith('on'))
        .toList();
    for (final k in bad) {
      n.attributes.remove(k);
    }
  }

  for (final img in node.querySelectorAll('img').toList()) {
    final real = img.attributes['zoomfile'] ??
        img.attributes['file'] ??
        img.attributes['data-original'] ??
        img.attributes['src'];
    final src = absolute(real);
    img.attributes['src'] = src;
    for (final k in ['width', 'height', 'file', 'zoomfile', 'data-original', 'onclick']) {
      img.attributes.remove(k);
    }
    final cls = src.contains('/static/image/smiley/') ? 'smiley' : 'post-img';
    img.attributes['class'] = cls;
  }

  for (final a in node.querySelectorAll('a').toList()) {
    final href = absolute(a.attributes['href']);
    a.attributes['href'] = href;
    if (href.startsWith(kOrigin)) a.attributes['data-inapp'] = '1';
  }

  for (final v in node.querySelectorAll('video, audio').toList()) {
    final src = v.attributes['src'];
    if (src != null) v.attributes['src'] = absolute(src);
    v.attributes.remove('autoplay');
  }

  // spoiler：把標題與內容抽出來，交給 Flutter 端畫成可展開區塊。
  //
  // 論壇的 .spoilerbody 帶著 style="display:none"（網頁版靠 JS 切換），
  // 照搬過來的話展開後渲染引擎會照著隱藏，變成點開一片空白 —— 圖片也不見。
  for (final sp in node.querySelectorAll('.spoiler').toList()) {
    final btn = sp.querySelector('.spoilerheader input');
    final label = attr(btn, 'value').trim();
    final body = sp.querySelector('.spoilerbody') ?? _lastElementChild(sp);
    final box = dom.Element.tag('div');
    box.attributes['data-spoiler'] = label.isEmpty ? '展開內容' : label;
    if (body != null) {
      final copy = body.clone(true);
      _unhide(copy);
      box.append(copy);
    }
    sp.replaceWith(box);
  }

  // 其他被 display:none 藏起來的區塊（購買後可見等）也一併還原，
  // 反正伺服器沒回傳的內容本來就不在 HTML 裡，看得到的就該畫出來
  _unhide(node);

  return node.innerHtml.trim();
}


/// 移除 display:none，並往下套用到所有子節點
void _unhide(dom.Element el) {
  for (final n in [el, ...el.querySelectorAll('*')]) {
    final style = n.attributes['style'];
    if (style == null || !style.contains('display')) continue;
    final cleaned = style
        .split(';')
        .where((d) => !RegExp(r'^\s*display\s*:\s*none\s*$', caseSensitive: false)
            .hasMatch(d))
        .join(';');
    if (cleaned.trim().isEmpty) {
      n.attributes.remove('style');
    } else {
      n.attributes['style'] = cleaned;
    }
  }
}

/// package:html 不支援 :last-child，只好自己走
dom.Element? _lastElementChild(dom.Element el) =>
    el.children.isEmpty ? null : el.children.last;

/// package:html 不支援 :first-of-type，自己取第一個指定標籤的子元素
dom.Element? firstChildTag(dom.Element? el, String tag) {
  if (el == null) return null;
  for (final c in el.children) {
    if (c.localName == tag) return c;
  }
  return null;
}

PageInfo parsePager(dom.Document doc) {
  final pg = doc.querySelector('.pg');
  if (pg == null) return const PageInfo();
  final cur = int.tryParse(txt(pg.querySelector('strong'))) ?? 1;
  var total = cur;
  for (final a in pg.querySelectorAll('a')) {
    final p = paramInt(a.attributes['href'], 'page') ?? 0;
    if (p > total) total = p;
    final n = digits(txt(a));
    if (n > total) total = n;
  }
  return PageInfo(page: cur, total: total);
}
