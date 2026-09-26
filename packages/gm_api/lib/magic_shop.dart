import 'package:html/dom.dart' as dom;

import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 道具商店、我的道具、道具記錄（Discuz 內建 home.php?mod=magic）。
///
/// 購買、贈送、使用、丟棄都是網頁上的彈窗表單 → 用 popup.dart 的 openPopup／submitPopup。
class MagicItem {
  const MagicItem({
    required this.key,
    required this.name,
    this.image = '',
    this.description = '',
    this.price = '',
    this.amount = '',
    this.soldOut = '',
    this.actions = const [],
  });

  /// 道具代號（商店：highlight、bump…；我的道具：magicid）
  final String key;
  final String name;
  final String image;
  final String description;

  /// 商店：「金币 5 枚/张」
  final String price;

  /// 我的道具：「数量: 10, 总重量: 200」
  final String amount;

  /// 「此道具缺货」
  final String soldOut;

  /// (按鈕文字, 彈窗網址)：購買／贈送／使用／丟棄
  final List<(String, String)> actions;
}

class MagicShopPage {
  const MagicShopPage({this.capacity = '', this.balance = '', this.items = const [], this.message});

  /// 道具包容量「200/200」
  final String capacity;

  /// 「金币 1276 枚」
  final String balance;
  final List<MagicItem> items;
  final String? message;
}

/// [mine]＝我的道具；否則是商店（[hot] 熱銷）
Future<MagicShopPage> fetchMagicShop({bool mine = false, bool hot = false}) async {
  final path = mine
      ? 'home.php?mod=magic&action=mybox'
      : 'home.php?mod=magic&action=shop${hot ? '&operation=hot' : ''}';
  return parseMagicShop(toDoc(await Api.instance.get(path, desktop: true)));
}

MagicShopPage parseMagicShop(dom.Document doc) {
  final items = <MagicItem>[];
  for (final li in doc.querySelectorAll('ul.mgcl > li')) {
    final img = li.querySelector('.mg_img img');
    final ps = li.children.where((e) => e.localName == 'p').toList();
    final name = txt(li.querySelector('p strong'));
    if (name.isEmpty) continue;
    final idAttr = attr(li.querySelector('.mg_img'), 'id');
    final actions = <(String, String)>[
      for (final a in li.querySelectorAll('p.mtn a'))
        if (attr(a, 'href').contains('operation=')) (sys(txt(a)), attr(a, 'href').replaceAll('&amp;', '&')),
    ];
    final keyFromHref = actions.isEmpty
        ? ''
        : (param(actions.first.$2, 'mid') ?? param(actions.first.$2, 'magicid') ?? '');
    var info = '';
    if (ps.length > 1) info = txt(ps[1]);
    items.add(MagicItem(
      key: keyFromHref.isNotEmpty ? keyFromHref : idAttr.replaceFirst('magic_', ''),
      name: sys(name),
      image: absoluteImage(attr(img, 'src')),
      description: sys(txt(li.querySelector('.tip_c'))),
      price: info.contains('枚') || info.contains('金币') ? sys(info) : '',
      amount: info.contains('数量') || info.contains('重量') ? sys(info) : '',
      soldOut: sys(txt(li.querySelector('p.mtn .xg1'))),
      actions: actions,
    ));
  }

  final tbmu = doc.querySelector('.tbmu');
  final cap = RegExp(r'容量:\s*(\d+)\s*/\s*(\d+)').firstMatch(txt(tbmu));
  // 後面緊接著「|积分兑换」連結，單位只取到分隔符號前
  final bal = RegExp(r'目前有\s*(\S+)\s*(\d+)\s*([^\s|｜]+)').firstMatch(txt(tbmu));
  return MagicShopPage(
    capacity: cap == null ? '' : '${cap.group(1)}/${cap.group(2)}',
    balance: bal == null ? '' : sys('${bal.group(1)} ${bal.group(2)} ${bal.group(3)}'),
    items: items,
    message: items.isEmpty ? noticeMessage(doc) : null,
  );
}

/// 道具記錄：uselog 使用、buylog 購買、givelog 贈送、receivelog 獲贈
enum MagicLogKind {
  use('uselog', '使用記錄'),
  buy('buylog', '購買記錄'),
  give('givelog', '贈送記錄'),
  receive('receivelog', '獲贈記錄');

  const MagicLogKind(this.op, this.label);
  final String op;
  final String label;
}

/// 一列記錄：表頭與各格文字一一對應（各種記錄的欄位不一樣，照表頭顯示）
class TableRows {
  const TableRows({this.headers = const [], this.rows = const [], this.pager = const PageInfo()});
  final List<String> headers;
  final List<List<String>> rows;
  final PageInfo pager;
}

Future<TableRows> fetchMagicLog(MagicLogKind kind, {int page = 1}) async {
  final html = await Api.instance.get(
      'home.php?mod=magic&action=log&operation=${kind.op}${page > 1 ? '&page=$page' : ''}',
      desktop: true);
  return parseTable(toDoc(html).querySelector('table.dt'), page: page, doc: toDoc(html));
}

/// 通用表格：第一列 th 當表頭，其餘每列各格文字
TableRows parseTable(dom.Element? table, {int page = 1, dom.Document? doc}) {
  if (table == null) return const TableRows();
  final headers = [for (final th in table.querySelectorAll('th')) sys(txt(th))];
  final rows = <List<String>>[];
  for (final tr in table.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.isEmpty) continue;
    rows.add([for (final td in tds) sys(txt(td))]);
  }
  return TableRows(
    headers: headers,
    rows: rows,
    pager: doc == null ? const PageInfo() : parsePager(doc, current: page),
  );
}
