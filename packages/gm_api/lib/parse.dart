import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 's2t.dart';
import 'http.dart';
import 'models.dart';

/// 是否把論壇的簡體內容轉成繁體。由 SettingsStore 設定，
/// 集中在解析層處理，UI 端就不必每個地方各自轉一次。
bool convertToTraditional = false;

String zh(String s) => convertToTraditional ? S2T.instance.convert(s) : s;

/// 介面語言是不是繁體。由 SettingsStore 設定
bool uiTraditional = true;

/// 系統文字（簽到頁的欄位、積分名稱、版塊名、論壇給的提示…）跟著介面語言走。
///
/// 使用者自己發的東西 —— 帖子標題、內文、留言 —— 一律用 `txt()` 保留原文，
/// 轉過的標題跟網頁版對不起來。想看繁體請用帖子頁上的翻譯鈕。
String sys(String s) => uiTraditional ? S2T.instance.convert(s) : s;

dom.Document toDoc(String html) => html_parser.parse(html);

/// 取文字並把連續空白（含 &nbsp;）收成單一空格
String txt(dom.Node? node) {
  if (node == null) return '';
  final s = node is dom.Element ? node.text : (node.text ?? '');
  return zh(s.replaceAll(RegExp(r'\s+'), ' ').trim());
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

/// 只認登出連結。
///
/// 不能拿 mycenter=1 當證據 —— 訪客版的底部導覽也有「我的」這個連結，
/// 會讓訪客頁被判成已登入（畫面就會出現「已登入」卻抓不到 uid 的矛盾狀態）。
bool isLoggedIn(dom.Document doc) =>
    doc.querySelector('a[href*="action=logout"]') != null;

/// 明確判定「這是訪客頁」——必須看到登入入口，不能只憑「沒有登出連結」。
///
/// inajax=1 的浮層片段（評分表單、評分紀錄）兩種標記都沒有，
/// 用缺少登出連結去推論會把使用者莫名其妙踢出登入狀態。
/// 這一頁是不是「論壇把我們轉到登入表單」。
///
/// 不能用 isGuestPage —— 訪客瀏覽公開板塊時頁尾一樣有登入連結，
/// 那樣會把每個公開板塊都擋成「需要登入」。
bool isLoginWall(dom.Document doc) => doc.querySelector('#loginform') != null;

bool isGuestPage(dom.Document doc) {
  if (isLoggedIn(doc)) return false;
  return doc.querySelector('#loginform') != null ||
      doc.querySelector('a[href*="action=login"]') != null ||
      doc.querySelector('a[href*="mod=logging"]') != null;
}

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
/// noto-emoji 的 SVG 換成同一個 repo 裡的 PNG。
///
/// **為什麼要換**：帖子裡的表情是刻意不攔截的（要維持行內排版），所以走
/// HTML 元件的預設 <img> 渲染——而那個用 Image.network，**它不會解 SVG**。
/// 結果使用者插的 noto-emoji 在原生與網頁版都畫不出來（跟 CORS 無關，
/// 自簽版一樣不會顯示）。同一個 repo 有 png/128/ 版本，換過去就能沿用
/// 預設的行內渲染，不必為了表情去動整個 HTML 的排版流程。
String? _pngForEmojiSvg(String? url) {
  if (url == null || !url.contains('noto-emoji')) return url;
  // 要用 replaceFirstMapped：Dart 的 replaceFirst 收的是字面字串，
  // 不會把 $1 當成捕獲群組展開。
  return url.replaceFirstMapped(
    RegExp(r'/svg/(emoji_[0-9a-fA-Fu_]+)\.svg'),
    (m) => '/png/128/${m[1]}.png',
  );
}

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
    // 圖片用 absoluteImage：網頁版連第三方圖床也要走代理
    final src = absoluteImage(_pngForEmojiSvg(real));
    img.attributes['src'] = src;
    // 尺寸要先讀下來再刪 —— 表情圖是靠它認出來的
    final w = int.tryParse(
        (img.attributes['width'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    final h = int.tryParse(
        (img.attributes['height'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));

    for (final k in ['width', 'height', 'file', 'zoomfile', 'data-original', 'onclick']) {
      img.attributes.remove(k);
    }

    // 論壇自己的表情在 /static/image/smiley/，但使用者也會插 noto-emoji 的
    // SVG（jsdelivr）。那些都寫著 width="15"，照內容圖畫會變成整排大圖。
    final small = (w != null && w <= 48) || (h != null && h <= 48);
    final isSmiley = src.contains('/static/image/smiley/') ||
        src.contains('noto-emoji') ||
        small;
    img.attributes['class'] = isSmiley ? 'smiley' : 'post-img';
    if (isSmiley && (w != null || h != null)) {
      // 原本多大就畫多大，別統一撐成 22
      img.attributes['data-size'] = '${w ?? h}';
    }
  }

  for (final a in node.querySelectorAll('a').toList()) {
    final href = absolute(a.attributes['href']);
    a.attributes['href'] = href;
    // 站內連結。網頁版走代理時 kOrigin 是自己的網域，
    // 但頁面裡仍可能出現論壇原網址，兩種都要認得。
    if (href.startsWith(kOrigin) || href.startsWith(kForumOrigin)) {
      a.attributes['data-inapp'] = '1';
    }
  }

  for (final v in node.querySelectorAll('video, audio').toList()) {
    final src = v.attributes['src'];
    if (src != null) v.attributes['src'] = absoluteImage(src);
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

  if (convertToTraditional) _convertTextNodes(node);

  return node.innerHtml.trim();
}

/// 只轉文字節點 —— 直接對整段 HTML 做字串替換會連標籤和網址一起改掉
void _convertTextNodes(dom.Node node) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      final t = child.text;
      if (t.trim().isNotEmpty) child.text = S2T.instance.convert(t);
    } else {
      _convertTextNodes(child);
    }
  }
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

/// `current` 是我們**要求**的頁數。有些列表（我的回覆、記錄廣場）的分頁列
/// 只有「上一頁／下一頁」，既沒有 `<strong>` 標目前頁、也沒有頁碼連結，
/// 光看 DOM 只會永遠算成第 1 頁，然後把「下一頁」的 page=3 當成總頁數。
PageInfo parsePager(dom.Document doc, {int current = 1}) {
  final pg = doc.querySelector('.pg');
  if (pg == null) return PageInfo(page: current);

  final strong = int.tryParse(txt(pg.querySelector('strong')));
  final cur = strong ?? current;

  var numbered = strong != null;
  var total = cur;
  for (final a in pg.querySelectorAll('a')) {
    // 上一頁／下一頁不是頁碼，不能拿來當總頁數
    if (a.classes.contains('nxt') || a.classes.contains('prev')) continue;
    if (a.parent?.classes.contains('pgb') ?? false) continue;
    final byHref = paramInt(a.attributes['href'], 'page') ?? 0;
    final byText = digits(txt(a));
    // 只有文字本身是數字才算頁碼連結
    if (byText > 0) numbered = true;
    final p = byText > 0 ? byText : byHref;
    if (p > total) total = p;
  }

  final hasNext = pg.querySelector('a.nxt') != null;
  final hasPrev = pg.querySelector('.pgb a') != null || cur > 1;

  // 沒有頁碼可看的話，總數只能猜：至少還有下一頁
  if (!numbered && hasNext && total <= cur) total = cur + 1;

  return PageInfo(
    page: cur,
    total: total < cur ? cur : total,
    hasNext: hasNext,
    hasPrev: hasPrev,
    numbered: numbered,
  );
}

/// 把一小段 HTML 轉純文字。勳章說明藏在 `tip` 屬性裡，是被跳脫過的 HTML
String plainText(String html) {
  if (html.isEmpty) return '';
  final t = txt(dom.Element.html('<div>$html</div>'));
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}


/// 空間的隱私牆：「抱歉！由于 XXX 的隐私设置，您不能访问当前内容」
String? privacyMessage(dom.Document doc) {
  final h = doc.querySelector('.nfl h2');
  final t = txt(h);
  return t.isEmpty ? null : t;
}

/// 論壇把訪客轉去登入頁時，回來的是一頁只有「如果您的浏览器没有自动跳转」的轉址頁
bool isRedirectToLogin(dom.Document doc, String html) =>
    html.contains('mod=logging') &&
    (html.contains('没有自动跳转') || html.contains('沒有自動跳轉'));
