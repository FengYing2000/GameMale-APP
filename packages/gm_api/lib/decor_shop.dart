import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 三個「買了會顯示在自己身上」的商店：頭銜稱號（tshuz_buyname）、
/// 多彩名片（k_usercard）、帖子背景（tshuz_bgshop）。
///
/// 購買／佩戴都是網頁上的 showWindow 彈窗 → 用 popup.dart 打開。
/// ⚠ 頭銜與背景的購買網址 GET 下去就直接扣款，一定要先跟使用者確認。
class ShopAction {
  const ShopAction({required this.label, required this.url, this.charges = false});
  final String label;

  /// 彈窗網址（相對）
  final String url;

  /// 按下去就會扣款（要先確認）
  final bool charges;
}

class DecorItem {
  const DecorItem({
    required this.id,
    required this.name,
    this.image = '',
    this.price = '',
    this.duration = '',
    this.info = const [],
    this.flag = '',
    this.actions = const [],
    this.textColor,
  });

  final int id;
  final String name;
  final String image;

  /// 「13 枚金币」「30 金币」
  final String price;

  /// 「13 天」「永久」「365 天」
  final String duration;

  /// 其他資訊列（購買時間、到期時間、大小、購買熱度…）：(標籤, 值)
  final List<(String, String)> info;

  /// 角標（名片的「免费」）
  final String flag;
  final List<ShopAction> actions;

  /// 名片的文字顏色（0xAARRGGBB），畫預覽用
  final int? textColor;
}

class DecorPage {
  const DecorPage({
    this.items = const [],
    this.categories = const [],
    this.pager = const PageInfo(),
    this.notes = const [],
    this.message,
  });

  final List<DecorItem> items;

  /// 分類（背景的側欄純色／底紋…）：(網址, 名稱, 數量, 目前)
  final List<(String, String, int, bool)> categories;
  final PageInfo pager;

  /// 頁面上的說明或補充資訊（目前使用的名片、購買紀錄…）
  final List<String> notes;
  final String? message;
}

String _clean(String s) => s.replaceAll('&amp;', '&');

/// showWindow('x', 'url') → url
String? _windowUrl(String onclick) =>
    RegExp(r"showWindow\(\s*'[^']*'\s*,\s*'([^']+)'").firstMatch(onclick)?.group(1);

// ── 頭銜稱號 ──────────────────────────────────────────

Future<DecorPage> fetchTitleShop({int page = 1}) async => parseTitleShop(toDoc(
    await Api.instance.get(
        page > 1 ? 'plugin.php?id=tshuz_buyname&mod=list&page=$page' : 'plugin.php?id=tshuz_buyname',
        desktop: true)), page: page);

Future<DecorPage> fetchMyTitles() async => parseTitleShop(
    toDoc(await Api.instance.get('plugin.php?id=tshuz_buyname&mod=manage', desktop: true)),
    mine: true);

/// 商店每列：ID、名稱、價格、期限、圖、購買鈕；
/// 我的稱號每列：記錄ID、名稱、購買時間、到期時間、圖、佩戴／取消佩戴／重新購買
DecorPage parseTitleShop(dom.Document doc, {int page = 1, bool mine = false}) {
  final items = <DecorItem>[];
  for (final tr in doc.querySelectorAll('#threadlist .bm_c tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 5) continue;
    final id = int.tryParse(txt(tds[0]));
    if (id == null) continue;
    final actions = <ShopAction>[
      for (final b in tr.querySelectorAll('button'))
        if (_windowUrl(attr(b, 'onclick')) case final url?)
          ShopAction(label: sys(txt(b)), url: _clean(url), charges: url.contains('mod=buy')),
    ];
    items.add(DecorItem(
      id: id,
      name: txt(tds[1]),
      image: absoluteImage(attr(tds[4].querySelector('img'), 'src')),
      price: mine ? '' : sys(txt(tds[2])),
      duration: sys(txt(tds[3])),
      info: mine ? [(sys('购买时间'), txt(tds[2])), (sys('到期时间'), sys(txt(tds[3])))] : const [],
      actions: actions,
    ));
  }
  final intro = txt(doc.querySelector('.mn > div'));
  return DecorPage(
    items: items,
    pager: parsePager(doc, current: page),
    notes: [if (!mine && intro.isNotEmpty) sys(intro)],
    message: items.isEmpty ? noticeMessage(doc) : null,
  );
}

// ── 多彩名片 ──────────────────────────────────────────

Future<DecorPage> fetchCardShop({bool byHeat = false, int page = 1}) async {
  final q = StringBuffer('k_usercard-style.html');
  final params = [if (byHeat) 'orderby=sales', if (page > 1) 'page=$page'];
  if (params.isNotEmpty) q.write('?${params.join('&')}');
  return parseCardShop(toDoc(await Api.instance.get(q.toString(), desktop: true)), page: page);
}

Future<DecorPage> fetchMyCards() async => parseCardShop(
    toDoc(await Api.instance.get('k_usercard-style.html?mod=mycard', desktop: true)),
    mine: true);

DecorPage parseCardShop(dom.Document doc, {int page = 1, bool mine = false}) {
  // 名片的背景圖與文字色在頁面的 <style> 裡：.cardstyle_ID { background: url('…') } color: #FFF
  final css = doc.querySelectorAll('style').map((e) => e.text).join('\n');
  int? colorOf(int id) {
    final m = RegExp('\\.cardstyle_$id\\s*\\{\\s*color:\\s*#([0-9A-Fa-f]{6})').firstMatch(css);
    return m == null ? null : int.parse('FF${m.group(1)}', radix: 16);
  }

  final items = <DecorItem>[];
  for (final it in doc.querySelectorAll('.item_list .item')) {
    final pics = it.querySelector('.pics');
    final id = int.tryParse(attr(pics, 'id').replaceFirst('card_', ''));
    if (id == null) continue;
    final strongs = it.querySelectorAll('.txt3 strong').map(txt).toList();
    final units = it.querySelectorAll('.txt3 span').map(txt).toList();
    final actions = <ShopAction>[
      for (final b in it.querySelectorAll('button, a[onclick*="showWindow"]'))
        if (_windowUrl(attr(b, 'onclick')) case final url?)
          ShopAction(label: sys(txt(b)), url: _clean(url), charges: url.contains('act=buy')),
    ];
    final heat = txt(it.querySelector('.item_sort'));
    items.add(DecorItem(
      id: id,
      name: sys(txt(it.querySelector('.txt1 strong'))),
      image: absoluteImage(attr(it.querySelector('img.item_pic'), 'src')),
      price: strongs.isNotEmpty ? sys('${strongs[0]} ${units.isNotEmpty ? units[0] : ''}'.trim()) : '',
      duration: strongs.length > 1 ? sys('${strongs[1]} ${units.length > 1 ? units[1] : ''}'.trim()) : '',
      info: [if (heat.isNotEmpty) (sys('购买热度'), heat.replaceAll(RegExp(r'[^0-9]'), ''))],
      flag: sys(txt(it.querySelector('.ico_flag2_hot'))),
      actions: actions,
      textColor: colorOf(id),
    ));
  }

  // 側欄：目前使用中的名片、過期時間
  final notes = <String>[];
  for (final bm in doc.querySelectorAll('.sd .bm')) {
    final title = txt(bm.querySelector('.bm_h h2'));
    if (!title.contains('正在使用')) continue;
    for (final li in bm.querySelectorAll('li')) {
      final t = txt(li);
      if (t.isNotEmpty && !t.contains('恢复默认')) notes.add(sys(t));
    }
  }
  return DecorPage(
    items: items,
    pager: parsePager(doc, current: page),
    notes: notes,
    message: items.isEmpty && !mine ? noticeMessage(doc) : null,
  );
}

/// 恢復預設名片（網頁：confirm 後整頁導過去）
Future<SubmitResult> resetUserCard() async {
  final html = await Api.instance.get('plugin.php?id=k_usercard:misc&act=reset', desktop: true);
  return submitResult(html, '恢復預設名片');
}

// ── 背景商店 ──────────────────────────────────────────

enum BgSection {
  side(1, '帖子側欄背景'),
  body(2, '帖子正文背景');

  const BgSection(this.pid, this.label);
  final int pid;
  final String label;
}

Future<DecorPage> fetchBgShop(BgSection section, {int cid = 0, int page = 1}) async {
  final q = StringBuffer('plugin.php?id=tshuz_bgshop&pid=${section.pid}');
  if (cid > 0) q.write('&cid=$cid');
  if (page > 1) q.write('&lpage=1&page=$page');
  return parseBgShop(toDoc(await Api.instance.get(q.toString(), desktop: true)), page: page);
}

Future<DecorPage> fetchMyBackgrounds() async => parseBgShop(
    toDoc(await Api.instance.get('plugin.php?id=tshuz_bgshop&mod=my', desktop: true)),
    mine: true);

DecorPage parseBgShop(dom.Document doc, {int page = 1, bool mine = false}) {
  final categories = <(String, String, int, bool)>[
    for (final a in doc.querySelectorAll('.myfenleilist a'))
      (
        _clean(attr(a, 'href')),
        sys(attr(a, 'title').isNotEmpty ? attr(a, 'title') : txt(a).replaceAll(RegExp(r'\d+$'), '')),
        int.tryParse(txt(a.querySelector('.myfenleicount'))) ?? 0,
        a.classes.contains('myon'),
      ),
  ];

  final items = <DecorItem>[];
  for (final b in doc.querySelectorAll('.myblok')) {
    final btn = b.querySelector('button[onclick*="buyBg"]');
    final m = RegExp(r"buyBg\('(\d+)','([^']*)','([^']*)','([^']*)'\)").firstMatch(attr(btn, 'onclick'));
    final info = <(String, String)>[];
    var price = '', days = '';
    for (final p in b.querySelectorAll('.myinfo p')) {
      final label = txt(p.querySelector('b')).replaceAll(RegExp(r'[:：]\s*$'), '');
      if (p.classes.contains('mz') || p.classes.contains('ac') || label.isEmpty) continue;
      final value = txt(p).replaceFirst(txt(p.querySelector('b')), '').trim();
      if (label.contains('积分')) {
        price = sys(value);
      } else if (label.contains('天数')) {
        days = sys(value);
      } else {
        info.add((sys(label), sys(value)));
      }
    }
    // 我的背景不知道長怎樣（這個帳號沒有）：除了購買之外的按鈕，只要是彈窗就收
    final actions = <ShopAction>[
      if (m != null)
        ShopAction(
          label: sys('购买'),
          url: 'plugin.php?id=tshuz_bgshop&mod=buy&item=${m.group(1)}&formhash=${m.group(4)}',
          charges: true,
        ),
      for (final other in b.querySelectorAll('button, a[onclick*="showWindow"]'))
        if (other != btn)
          if (_windowUrl(attr(other, 'onclick')) case final url?)
            ShopAction(label: sys(txt(other)), url: _clean(url), charges: url.contains('mod=buy')),
    ];
    final name = txt(b.querySelector('.myinfo p.mz b'));
    final id = int.tryParse(m?.group(1) ?? '') ??
        int.tryParse(RegExp(r'/(\d+)\.\w+').firstMatch(attr(b.querySelector('.myimg img'), 'src'))?.group(1) ?? '') ??
        0;
    items.add(DecorItem(
      id: id,
      name: sys(name.isNotEmpty ? name : attr(b.querySelector('.myimg img'), 'alt')),
      image: absoluteImage(attr(b.querySelector('.myimg img'), 'src')),
      price: price,
      duration: days,
      info: info,
      actions: actions,
    ));
  }

  final notes = <String>[
    if (mine)
      for (final l in (doc.querySelector('.buylog')?.innerHtml ?? '').split(RegExp(r'<br\s*/?>|</li>|</p>')))
        if (sys(txt(toDoc(l).body)) case final t when t.isNotEmpty) t,
  ];
  return DecorPage(
    items: items,
    categories: categories,
    pager: parsePager(doc, current: page),
    notes: notes,
    message: items.isEmpty && !mine ? noticeMessage(doc) : null,
  );
}
