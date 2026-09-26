import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 日常卡片＝積分抽獎外掛（it618_award）。
///
/// 全部是 GET `plugin.php?id=it618_award:ajax&formhash=…&ac=…`，回的是 HTML 片段、
/// 用 `it618_split` 分段。
///
/// ⚠ `ac=getwapaward` 就是「抽一次」（GET 也會扣金幣），只能在使用者按下去時呼叫。
/// ⚠ `ac=wapaward_get` 不帶 `ac1=myaward` 是全站紀錄，一次回 9 MB，絕對不要抓。
const _page = 'it618_award-award.html';

String _ajax(String formhash, String ac) =>
    'plugin.php?id=it618_award:ajax&formhash=$formhash&ac=$ac';

class LotteryPrize {
  const LotteryPrize({required this.name, this.reward = ''});

  /// 「I 等卡片」
  final String name;

  /// 「25 血液」
  final String reward;
}

class LotteryInfo {
  const LotteryInfo({
    this.image = '',
    this.rule = '',
    this.cost = '',
    this.perDay = 0,
    this.used = 0,
    this.prizes = const [],
    this.formhash = '',
  });

  /// 抽獎按鈕的圖
  final String image;

  /// 「每次抽奖需要 2 金币，每天每会员可以抽奖 1 次，您已抽奖了 1 次」
  final String rule;
  final String cost;
  final int perDay;
  final int used;
  final List<LotteryPrize> prizes;
  final String formhash;

  bool get canDraw => perDay == 0 || used < perDay;
}

class LotteryRecord {
  const LotteryRecord({this.cost = '', this.prize = '', this.reward = '', this.time = ''});
  final String cost;
  final String prize;
  final String reward;
  final String time;
}

class LotteryMine {
  const LotteryMine({this.summary = const [], this.records = const [], this.pager = const PageInfo()});

  /// 第一格：各積分餘額、花費總積分、獎勵總積分（一行一條）
  final List<String> summary;
  final List<LotteryRecord> records;
  final PageInfo pager;
}

/// 抽獎頁要先拿 formhash（ajax 都要帶）
Future<String> _formhash() async {
  final f = Api.instance.formhash;
  if (f != null && f.isNotEmpty) return f;
  final html = await Api.instance.get(_page, desktop: true);
  return formhashOf(toDoc(html), html) ?? '';
}

Future<LotteryInfo> fetchLottery() async {
  final hash = await _formhash();
  final html = await Api.instance.get(_ajax(hash, 'getwapgoods'), desktop: true);
  return parseLottery(html, formhash: hash);
}

LotteryInfo parseLottery(String html, {String formhash = ''}) {
  final parts = html.split('it618_split');
  final head = toDoc(parts.first);
  final tip = head.querySelector('#tips_credit');
  final nums = tip?.querySelectorAll('font').map(txt).toList() ?? const <String>[];
  final prizes = <LotteryPrize>[];
  if (parts.length > 1) {
    for (final td in toDoc('<table>${parts[1]}</table>').querySelectorAll('td')) {
      final name = txt(td.querySelector('span'));
      if (name.isEmpty) continue;
      final reward = txt(td).replaceFirst(name, '').replaceFirst(RegExp(r'积分奖励[:：]'), '').trim();
      prizes.add(LotteryPrize(name: sys(name), reward: sys(reward)));
    }
  }
  final unit = RegExp(r'需要\s*\d+\s*(\S+?)\s*[，,]').firstMatch(txt(tip))?.group(1) ?? '';
  return LotteryInfo(
    image: absoluteImage(attr(head.querySelector('img'), 'src')),
    rule: sys(txt(tip)),
    cost: nums.isNotEmpty ? sys('${nums[0]} $unit'.trim()) : '',
    perDay: nums.length > 1 ? int.tryParse(nums[1]) ?? 0 : 0,
    used: nums.length > 2 ? int.tryParse(nums[2]) ?? 0 : 0,
    prizes: prizes,
    formhash: formhash,
  );
}

/// 抽一次。回傳 (有沒有抽到, 論壇的話)
Future<(bool, String)> drawLottery(String formhash) async {
  final data = await Api.instance.get(_ajax(formhash, 'getwapaward'), desktop: true);
  return parseDrawResult(data);
}

(bool, String) parseDrawResult(String data) {
  final parts = data.split('it618_split');
  String clean(String s) => sys(txt(toDoc(s).body));
  // 網頁：有 split 就 alert 第二段（抽到了），沒有就整段是錯誤訊息
  if (parts.length > 1) return (true, clean(parts[1]));
  return (false, clean(data));
}

Future<LotteryMine> fetchLotteryMine({int page = 1}) async {
  final hash = await _formhash();
  final html = await Api.instance.get(
      'plugin.php?id=it618_award:ajax&page=$page&ac1=myaward&formhash=$hash&ac=wapaward_get',
      desktop: true);
  return parseLotteryMine(html, page: page);
}

LotteryMine parseLotteryMine(String html, {int page = 1}) {
  final parts = html.split('it618_split');
  final rows = toDoc('<table>${parts.first}</table>').querySelectorAll('td');
  final summary = <String>[];
  final records = <LotteryRecord>[];
  for (final td in rows) {
    final text = txt(td);
    if (text.contains('花费总积分') || td.querySelector('img') != null && records.isEmpty && summary.isEmpty) {
      // 第一格：餘額＋總計，<br> 分行
      for (final line in td.innerHtml.split(RegExp(r'<br\s*/?>'))) {
        final t = sys(txt(toDoc(line).body));
        if (t.isNotEmpty) summary.add(t);
      }
      continue;
    }
    final m = RegExp(r'花了\s*(\S+)\s*(\S+?)\s*抽到了\s*(.+?)\s*积分奖励[:：]\s*(.+?)\s*(\d{4}-\d{2}-\d{2}[\d: ]*)$')
        .firstMatch(text);
    if (m == null) continue;
    records.add(LotteryRecord(
      cost: sys('${m.group(1)} ${m.group(2)}'),
      prize: sys(m.group(3)!),
      reward: sys(m.group(4)!),
      time: m.group(5)!.trim(),
    ));
  }
  var total = page;
  if (parts.length > 1) {
    final nums = RegExp(r'page=(\d+)').allMatches(parts[1]).map((m) => int.parse(m.group(1)!));
    if (nums.isNotEmpty) total = nums.reduce((a, b) => a > b ? a : b);
  }
  return LotteryMine(
    summary: summary,
    records: records,
    pager: PageInfo(
      page: page,
      total: total < page ? page : total,
      hasNext: total > page,
      hasPrev: page > 1,
    ),
  );
}
