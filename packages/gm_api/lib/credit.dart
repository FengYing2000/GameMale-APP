import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult, unwrapAjax;
import 'http.dart';
import 'magic_shop.dart' show TableRows, parseTable;
import 'models.dart';
import 'parse.dart';

/// 積分：餘額、兌換（「血液祭獻」＝用血液換其他積分）、積分記錄。
class CreditBalance {
  const CreditBalance({required this.name, required this.value, this.icon = ''});

  /// 旅程
  final String name;

  /// 「297 里」
  final String value;
  final String icon;
}

/// 可兌換的積分
class CreditOption {
  const CreditOption({required this.id, required this.name, this.unit = '', this.ratio = 1});

  /// 積分編號（1 旅程、3 血液…）
  final String id;
  final String name;
  final String unit;

  /// 兌換比率（網頁 option 的 ratio 屬性）
  final double ratio;
}

class CreditExchangePage {
  const CreditExchangePage({
    this.balances = const [],
    this.to = const [],
    this.from = const [],
    this.tax = 0,
    this.formhash = '',
    this.message,
  });

  final List<CreditBalance> balances;

  /// 可以換到的積分
  final List<CreditOption> to;

  /// 拿來換的積分（GameMale 只有血液）
  final List<CreditOption> from;

  /// 交易稅（0.15＝15%）
  final double tax;
  final String formhash;
  final String? message;

  /// 換到 [amount] 個 [target]，要花多少 [source]（照網頁的算法）
  int cost(CreditOption target, CreditOption source, int amount) {
    if (amount <= 0 || target.id == source.id || source.ratio == 0) return 0;
    final v = target.ratio / source.ratio * amount * (1 + tax);
    return target.ratio < source.ratio ? v.ceil() : v.floor();
  }
}

const _exchangeUrl = 'home.php?mod=spacecp&ac=credit&op=exchange';

Future<CreditExchangePage> fetchCreditExchange() async =>
    parseCreditExchange(toDoc(await Api.instance.get(_exchangeUrl, desktop: true)));

CreditExchangePage parseCreditExchange(dom.Document doc) {
  List<CreditOption> options(String selector) => [
        for (final o in doc.querySelectorAll('$selector option'))
          CreditOption(
            id: attr(o, 'value'),
            name: sys(attr(o, 'title').isNotEmpty ? attr(o, 'title') : txt(o)),
            unit: sys(attr(o, 'unit')),
            ratio: double.tryParse(attr(o, 'ratio')) ?? 1,
          ),
      ];
  final taxText = txt(doc.querySelector('#taxpercent'));
  final tax = double.tryParse(RegExp(r'([\d.]+)\s*%').firstMatch(taxText)?.group(1) ?? '');
  return CreditExchangePage(
    balances: parseBalances(doc),
    to: options('#tocredits'),
    from: options('#fromcredits_0'),
    tax: tax == null ? 0 : tax / 100,
    formhash: attr(doc.querySelector('#exchangeform input[name="formhash"]'), 'value'),
    message: doc.querySelector('#exchangeform') == null ? noticeMessage(doc) : null,
  );
}

/// 積分頁頂端那排餘額（ul.creditl）
List<CreditBalance> parseBalances(dom.Document doc) {
  final out = <CreditBalance>[];
  for (final li in doc.querySelectorAll('ul.creditl li')) {
    final em = li.querySelector('em');
    final name = txt(em).replaceAll(RegExp(r'[:：]\s*$'), '').trim();
    if (name.isEmpty) continue;
    out.add(CreditBalance(
      name: sys(name),
      value: sys(txt(li).replaceFirst(txt(em), '').trim()),
      icon: absoluteImage(attr(em?.querySelector('img'), 'src')),
    ));
  }
  return out;
}

/// 兌換。要論壇的登入密碼（網頁也要）；密碼只送去論壇，App 不留
Future<SubmitResult> exchangeCredit({
  required CreditExchangePage page,
  required CreditOption target,
  required CreditOption source,
  required int amount,
  required String password,
}) async {
  final xml = await Api.instance.post('$_exchangeUrl&handlekey=credit&inajax=1', {
    'formhash': page.formhash,
    'operation': 'exchange',
    'exchangesubmit': 'true',
    'outi': '0',
    'exchangeamount': '$amount',
    'tocredits': target.id,
    'fromcredits': source.id,
    'password': password,
  }, desktop: true);
  return submitResult(unwrapAjax(xml), '兌換');
}

/// 積分記錄（操作、積分變更、詳情、時間）
Future<TableRows> fetchCreditLog({int page = 1}) async {
  final html = await Api.instance.get(
      'home.php?mod=spacecp&ac=credit&op=log${page > 1 ? '&page=$page' : ''}',
      desktop: true);
  final doc = toDoc(html);
  return parseTable(doc.querySelector('table.dt'), page: page, doc: doc);
}
