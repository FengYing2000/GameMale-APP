import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult, unwrapAjax;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 勳章外掛（wodexunzhang）。所有頁面與動作都打同一支：
/// `plugin.php?id=wodexunzhang:showxunzhang`，用 action 參數分頁與分動作。
///
/// 分頁：商城（預設）、榮譽 showRongyu、獎勵 showJiangli、二手市場 showjishou、
/// 交易角 trade、勳章組合 combo、我的勳章 my、排行榜 paihang。
const _base = 'plugin.php?id=wodexunzhang:showxunzhang';

enum MedalTab {
  shop('', '勳章商城'),
  honor('showRongyu', '榮譽勳章'),
  reward('showJiangli', '獎勵勳章'),
  market('showjishou', '二手市場'),
  trade('trade', '交易角'),
  combo('combo', '勳章組合'),
  mine('my', '我的勳章'),
  rank('paihang', '排行榜');

  const MedalTab(this.action, this.label);
  final String action;
  final String label;
}

class MedalCategory {
  const MedalCategory({required this.fid, required this.name, this.count = 0, this.current = false});
  final int fid;
  final String name;
  final int count;
  final bool current;
}

/// 勳章上的一顆按鈕（網頁的 wodexunzhangAction(this, kind, id, arg)）
class MedalAction {
  const MedalAction({required this.kind, required this.id, this.arg = '', this.label = ''});

  /// goumai 購買／zengsong 贈送／lingqu 領取／goumaijishou 買寄售品／
  /// huishou 回收／jishou 寄售／UPLV 升級／xuqi 續期
  final String kind;

  /// 送出時放進表單的那個編號（注意寄售帶的是勳章 ID，不是我的勳章編號）
  final int id;

  /// 網頁 confirm 用的附帶資訊：價格（金币 450）、寄售上限（804）、續期說明
  final String arg;
  final String label;

  bool get spends => kind == 'goumai' || kind == 'goumaijishou' || kind == 'UPLV' || kind == 'xuqi';
}

class MedalItem {
  const MedalItem({
    required this.id,
    required this.name,
    this.image = '',
    this.badge = '',
    this.description = '',
    this.status = '',
    this.recyclable,
    this.renewable,
    this.consignable,
    this.info = const [],
    this.condition = '',
    this.effects = const [],
    this.actions = const [],
    this.userMedalId,
    this.shown,
  });

  /// tip 的編號：商城是勳章 ID；二手市場是寄售單號；我的勳章是我的勳章編號
  final int id;
  final String name;
  final String image;

  /// 名稱前的小標：「可升级」「等级 1」
  final String badge;
  final String description;

  /// 狀態字：已拥有／结束购买／不可购买！／无货啦！／不可领取（有按鈕時通常是空的）
  final String status;

  final bool? recyclable;
  final bool? renewable;
  final bool? consignable;

  /// 其餘資訊列：(標籤, 值)，例如 (购买价格, 金币 450)、(剩余库存, 61)、(勋章作者, xxx)、(有效期, 1 天)
  final List<(String, String)> info;

  /// 領取條件，或「可領取用戶」名單
  final String condition;

  /// 屬性加成（發帖 血液 +1、觸發機率 5%）
  final List<String> effects;
  final List<MedalAction> actions;

  /// 我的勳章才有：排序／顯示開關用的編號
  final int? userMedalId;

  /// 我的勳章才有：是否在帖子裡顯示
  final bool? shown;

  String infoOf(String label) {
    for (final (l, v) in info) {
      if (l.contains(label)) return v;
    }
    return '';
  }

  String get price => infoOf('价格');
  String get stock => infoOf('库存');
}

class MedalGroup {
  const MedalGroup({required this.title, required this.items});
  final String title;
  final List<MedalItem> items;
}

/// 「我的勳章統計」一格：分類、持有數、上限
class MedalStat {
  const MedalStat({required this.name, required this.owned, required this.limit, this.full = false});
  final String name;
  final int owned;
  final String limit;
  final bool full;
}

/// 頁尾的勳章紀錄：誰在什麼時候領了什麼
class MedalRecord {
  const MedalRecord({required this.user, this.uid, this.avatar = '', this.text = '', this.medal = ''});
  final String user;
  final int? uid;
  final String avatar;
  final String text;
  final String medal;
}

class MedalPage {
  const MedalPage({
    this.categories = const [],
    this.groups = const [],
    this.stats = const [],
    this.records = const [],
    this.pager = const PageInfo(),
    this.formhash = '',
    this.idField = 'medalid',
    this.message,
  });

  final List<MedalCategory> categories;
  final List<MedalGroup> groups;
  final List<MedalStat> stats;
  final List<MedalRecord> records;
  final PageInfo pager;
  final String formhash;

  /// 表單裡放編號的欄位：商城類是 medalid，我的勳章是 userMedalid
  final String idField;

  /// 頁面沒內容時論壇給的話（未登入、權限不足）
  final String? message;

  List<MedalItem> get items => [for (final g in groups) ...g.items];
}

String medalUrl(MedalTab tab, {int fid = 0, int page = 1}) {
  final q = StringBuffer(_base);
  if (tab.action.isNotEmpty) q.write('&action=${tab.action}');
  if (fid > 0) q.write('&fid=$fid');
  if (page > 1) q.write('&page=$page');
  return q.toString();
}

Future<MedalPage> fetchMedalPage(MedalTab tab, {int fid = 0, int page = 1}) async {
  final html = await Api.instance.get(medalUrl(tab, fid: fid, page: page), desktop: true);
  return parseMedalPage(toDoc(html), page: page);
}

MedalPage parseMedalPage(dom.Document doc, {int page = 1}) {
  final categories = <MedalCategory>[
    for (final a in doc.querySelectorAll('.myfenleilist a'))
      if (paramInt(attr(a, 'href').replaceAll('&amp;', '&'), 'fid') case final fid?)
        MedalCategory(
          fid: fid,
          name: sys(attr(a, 'title').isNotEmpty ? attr(a, 'title') : txt(a)),
          count: int.tryParse(txt(a.querySelector('.myfenleicount'))) ?? 0,
          current: a.classes.contains('myon'),
        ),
  ];

  final groups = <MedalGroup>[];
  for (final g in doc.querySelectorAll('.my_fenlei')) {
    final items = [
      for (final b in g.querySelectorAll('.myblok'))
        if (parseMedalBlock(b) case final m?) m,
    ];
    if (items.isEmpty) continue;
    groups.add(MedalGroup(title: sys(txt(g.querySelector('.my_biaoti'))), items: items));
  }

  final stats = <MedalStat>[
    for (final s in doc.querySelectorAll('.stat_grid .stat_item'))
      MedalStat(
        // 「游戏男从 Male ≤11」的上限後面已經有了，名稱就不重複
        name: sys(txt(s.querySelector('.stat_name')).replaceFirst(RegExp(r'\s*[≤<]=?\s*\d+\s*$'), '')),
        owned: int.tryParse(txt(s.querySelector('.stat_count strong'))) ?? 0,
        limit: txt(s.querySelector('.stat_count span')),
        full: s.classes.contains('is_full'),
      ),
  ];

  final records = <MedalRecord>[];
  for (final li in doc.querySelectorAll('ul.el li')) {
    final user = li.querySelector('a.xi2');
    if (user == null) continue;
    final medal = txt(li.querySelector('b'));
    final full = txt(li);
    records.add(MedalRecord(
      user: txt(user),
      uid: _uidOf(attr(user, 'href')),
      avatar: absoluteImage(attr(li.querySelector('img'), 'src')),
      medal: sys(medal),
      text: sys(full.replaceFirst(txt(user), '').trim()),
    ));
  }

  final form = doc.querySelector('#medalid_f');
  final idField = form?.querySelector('input[name="userMedalid"]') != null ? 'userMedalid' : 'medalid';

  return MedalPage(
    categories: categories,
    groups: groups,
    stats: stats,
    records: records,
    pager: parsePager(doc, current: page),
    formhash: attr(doc.querySelector('#medalid_f input[name="formhash"]') ??
        doc.querySelector('input[name="formhash"]'), 'value'),
    idField: idField,
    message: groups.isEmpty && stats.isEmpty ? noticeMessage(doc) : null,
  );
}

/// 一枚勳章（.myblok）
MedalItem? parseMedalBlock(dom.Element b) {
  final tip = b.querySelector('.mytip');
  final idm = RegExp(r'(\d+)$').firstMatch(attr(tip, 'id'));
  final key = int.tryParse(attr(b, 'key'));
  final id = int.tryParse(idm?.group(1) ?? '') ?? key;
  if (id == null) return null;

  final img = b.querySelector('.myimg img');
  final name = attr(b.querySelector('.myimg p[title]'), 'title').isNotEmpty
      ? attr(b.querySelector('.myimg p[title]'), 'title')
      : attr(img, 'alt');

  final actions = <MedalAction>[];
  for (final btn in b.querySelectorAll('.myimg button')) {
    final m = RegExp(r"wodexunzhangAction\(this,\s*'(\w+)',\s*(\d+)\s*(?:,\s*'?([^')]*)'?)?\)")
        .firstMatch(attr(btn, 'onclick'));
    if (m == null) continue;
    actions.add(MedalAction(
      kind: m.group(1)!,
      id: int.parse(m.group(2)!),
      arg: (m.group(3) ?? '').replaceAll('&nbsp;', ' ').trim(),
      label: sys(txt(btn)),
    ));
  }

  bool? recyclable, renewable, consignable;
  final info = <(String, String)>[];
  final effects = <String>[];
  var condition = '';
  var first = true;
  for (final p in tip?.querySelectorAll('p.jiage') ?? const <dom.Element>[]) {
    if (p.classes.contains('lingqu')) {
      // 「领取条件<br/><b>…</b>」或「可领取用户：<br/><b>名單</b>」
      final head = txt(p).replaceFirst(txt(p.querySelector('b')), '').trim();
      final body = txt(p.querySelector('b'));
      condition = sys('$head ${body.isEmpty ? '' : body}'.trim());
      continue;
    }
    if (p.classes.contains('shuxing')) {
      effects.add(sys(txt(p)));
      continue;
    }
    final bold = p.querySelector('b');
    final value = txt(bold);
    final label = txt(p).replaceFirst(value, '').trim();
    if (first && label.isEmpty && RegExp('回收|续期|寄售').hasMatch(value)) {
      recyclable = !value.contains('不可回收') && value.contains('回收') ? true : (value.contains('不可回收') ? false : null);
      renewable = !value.contains('不可续期') && value.contains('续期') ? true : (value.contains('不可续期') ? false : null);
      consignable = !value.contains('不可寄售') && value.contains('寄售') ? true : (value.contains('不可寄售') ? false : null);
      first = false;
      continue;
    }
    first = false;
    if (label.isEmpty && value.isEmpty) continue;
    info.add((sys(label), sys(value)));
  }

  final xs = b.querySelector('input.xianshi_js');
  return MedalItem(
    id: id,
    name: sys(name),
    image: absoluteImage(attr(img, 'src')),
    badge: sys(txt(tip?.querySelector('p.mingcheng b'))),
    description: sys(txt(tip?.querySelector('p.shuoming'))),
    status: sys(txt(b.querySelector('.myimg p em'))),
    recyclable: recyclable,
    renewable: renewable,
    consignable: consignable,
    info: info,
    condition: condition,
    effects: effects,
    actions: actions,
    userMedalId: key,
    shown: xs?.attributes.containsKey('checked'),
  );
}

/// 勳章按鈕的動作（購買、領取、回收、寄售、升級、續期、買寄售品）。
///
/// 網頁是整頁表單 POST，回來是一頁提示。[page] 決定編號放哪個欄位；
/// 寄售要帶價格 [price]（1～上限）。
Future<SubmitResult> medalAction(MedalPage page, MedalAction a, {int? price}) async {
  final fields = <String, String>{
    'formhash': page.formhash.isNotEmpty ? page.formhash : (Api.instance.formhash ?? ''),
    'action': a.kind,
    page.idField: '${a.id}',
  };
  if (a.kind == 'jishou') fields['jishoujiage'] = '${price ?? 0}';
  final html = await Api.instance.post(_base, fields, desktop: true);
  return submitResult(html, _what(a.kind));
}

String _what(String kind) => switch (kind) {
      'goumai' || 'goumaijishou' => '購買',
      'lingqu' => '領取',
      'huishou' => '回收',
      'jishou' => '寄售',
      'UPLV' => '升級',
      'xuqi' => '續期',
      _ => '操作',
    };

/// 我的勳章：切換「在帖子裡顯示」。網頁是 ajax、不帶 formhash
Future<void> setMedalShown(int userMedalId, bool shown) async {
  await Api.instance.post(_base, {
    'xianshi': shown ? '1' : '0',
    'user_id': '$userMedalId',
    'action': 'newXianshi',
  }, desktop: true);
}

/// 我的勳章：拖曳排序後的新順序（我的勳章編號，逗號分隔）
Future<void> setMedalOrder(List<int> userMedalIds) async {
  await Api.instance.post(_base, {
    'newOrder': userMedalIds.join(','),
    'action': 'newOrder',
  }, desktop: true);
}

// ── 贈送 ─────────────────────────────────────────────

/// 贈送前先驗 UID：回傳對方暱稱，查無此人回 null
Future<String?> verifyMedalGiftUid(int uid, String formhash) async {
  final xml = await Api.instance.get(
      '$_base&formhash=$formhash&action=yzuid&uid=$uid&inajax=1&ajaxtarget=username',
      desktop: true);
  final doc = toDoc(unwrapAjax(xml));
  if (doc.querySelector('#checkUID') == null) return null;
  final t = txt(doc.body).trim();
  return t.isEmpty ? '$uid' : t;
}

/// 送出贈送
Future<SubmitResult> giftMedal({
  required int medalId,
  required int uid,
  required String message,
  required String formhash,
}) async {
  final xml = await Api.instance.get(
      '$_base&formhash=$formhash&action=zengsongAction&medalid=$medalId'
      '&zs_uid=$uid&zs_text=${Uri.encodeQueryComponent(message)}&checkUID=$uid'
      '&inajax=1&ajaxtarget=medalid_zs',
      desktop: true);
  return submitResult(unwrapAjax(xml), '贈送');
}

// ── 勳章組合（唯讀）───────────────────────────────────

class MedalCombo {
  const MedalCombo({
    required this.name,
    this.status = '',
    this.active = false,
    this.description = '',
    this.progress = '',
    this.medals = const [],
    this.effects = const [],
  });
  final String name;

  /// 已激活／差 3 枚
  final String status;
  final bool active;
  final String description;

  /// 0/3
  final String progress;

  /// (名稱, 圖, 已擁有)
  final List<(String, String, bool)> medals;
  final List<String> effects;
}

class MedalComboPage {
  const MedalComboPage({this.summary = '', this.bonuses = const [], this.combos = const []});

  /// 已激活 1 / 97 個組合
  final String summary;

  /// 目前生效的組合加成：(時機, 加成, 機率)
  final List<(String, String, String)> bonuses;
  final List<MedalCombo> combos;
}

Future<MedalComboPage> fetchMedalCombos() async =>
    parseMedalCombos(toDoc(await Api.instance.get(medalUrl(MedalTab.combo), desktop: true)));

MedalComboPage parseMedalCombos(dom.Document doc) {
  final title = doc.querySelector('.combo_summary_title span');
  return MedalComboPage(
    summary: sys(txt(title)),
    bonuses: [
      for (final b in doc.querySelectorAll('.combo_bonus_item'))
        (sys(txt(b.querySelector('span'))), sys(txt(b.querySelector('b'))), sys(txt(b.querySelector('em')))),
    ],
    combos: [
      for (final c in doc.querySelectorAll('.medal_combo_card'))
        MedalCombo(
          name: sys(txt(c.querySelector('h3'))),
          status: sys(txt(c.querySelector('.combo_status'))),
          active: c.classes.contains('is_active'),
          description: sys(txt(c.querySelector('.combo_description'))),
          progress: txt(c.querySelector('.combo_medal_title span')),
          medals: [
            for (final m in c.querySelectorAll('.combo_medal'))
              (
                sys(attr(m, 'title').isNotEmpty ? attr(m, 'title') : txt(m.querySelector('p'))),
                absoluteImage(attr(m.querySelector('img'), 'src')),
                m.classes.contains('owned'),
              ),
          ],
          effects: [
            for (final p in c.querySelectorAll('.combo_effects p'))
              if (!p.classes.contains('no_effect') && txt(p).isNotEmpty) sys(txt(p)),
          ],
        ),
    ],
  );
}

// ── 交易角 ────────────────────────────────────────────

class TradeMedal {
  const TradeMedal({required this.id, required this.name, this.image = '', this.category = ''});
  final int id;
  final String name;
  final String image;

  /// 分類 fid（篩選用）
  final String category;
}

class TradeOrder {
  const TradeOrder({
    required this.no,
    required this.user,
    this.uid,
    this.avatar = '',
    this.time = '',
    this.offer = const [],
    this.want = const [],
    this.note = '',
    this.form,
  });

  /// 單號 #374
  final String no;
  final String user;
  final int? uid;
  final String avatar;
  final String time;

  /// 對方提供／對方想要：(名稱, 圖)
  final List<(String, String)> offer;
  final List<(String, String)> want;

  /// 沒辦法成交的原因（你尚未集齐对方想要的勋章）
  final String note;

  /// 頁面上給的動作表單（確認交易、取消…），照原樣送出
  final TradeForm? form;
}

/// 交易單上的按鈕表單：隱藏欄位＋送出鈕，原封重送
class TradeForm {
  const TradeForm({required this.fields, required this.label, this.confirm = ''});
  final Map<String, String> fields;
  final String label;

  /// 網頁送出前問的那句話
  final String confirm;
}

class TradePage {
  const TradePage({
    this.notice = '',
    this.categories = const [],
    this.myMedals = const [],
    this.allMedals = const [],
    this.orders = const [],
    this.maxOffer = 4,
    this.maxWant = 4,
    this.fee = '',
    this.formhash = '',
    this.pager = const PageInfo(),
  });

  /// 規則說明
  final String notice;

  /// 分類：(fid, 名稱)
  final List<(String, String)> categories;
  final List<TradeMedal> myMedals;
  final List<TradeMedal> allMedals;
  final List<TradeOrder> orders;
  final int maxOffer;
  final int maxWant;

  /// 發布費（25 金币）
  final String fee;
  final String formhash;
  final PageInfo pager;
}

Future<TradePage> fetchTradePage({int page = 1}) async => parseTradePage(
    toDoc(await Api.instance.get(medalUrl(MedalTab.trade, page: page), desktop: true)),
    page: page);

TradePage parseTradePage(dom.Document doc, {int page = 1}) {
  List<TradeMedal> choices(String field) => [
        for (final l in doc.querySelectorAll('label.trade_medal_choice'))
          if (l.querySelector('input[name="$field"]') case final input?)
            TradeMedal(
              id: int.tryParse(attr(input, 'value')) ?? 0,
              name: sys(txt(l.querySelector('span'))),
              image: absoluteImage(attr(l.querySelector('img'), 'src')),
              category: attr(l, 'data-category'),
            ),
      ];

  final cats = <(String, String)>[];
  for (final b in doc.querySelectorAll('#trade_want_categories button')) {
    final m = RegExp(r"'want','(\w+)'").firstMatch(attr(b, 'onclick'));
    if (m == null || m.group(1) == 'all') continue;
    cats.add((m.group(1)!, sys(txt(b))));
  }

  final notice = doc.querySelector('.trade_notice');
  final strongs = notice?.querySelectorAll('strong').map(txt).toList() ?? const <String>[];

  final orders = <TradeOrder>[];
  for (final o in doc.querySelectorAll('.trade_order')) {
    final user = o.querySelector('.trade_user a');
    final sides = o.querySelectorAll('.trade_side');
    List<(String, String)> medals(int i) => i >= sides.length
        ? const []
        : [
            for (final m in sides[i].querySelectorAll('.trade_medal'))
              (sys(txt(m.querySelector('span'))), absoluteImage(attr(m.querySelector('img'), 'src'))),
          ];
    TradeForm? form;
    final f = o.querySelector('.trade_actions form');
    if (f != null) {
      final fields = <String, String>{
        for (final i in f.querySelectorAll('input'))
          if (attr(i, 'name').isNotEmpty) attr(i, 'name'): attr(i, 'value'),
      };
      final btn = f.querySelector('button');
      if (btn != null && attr(btn, 'name').isNotEmpty) {
        fields[attr(btn, 'name')] = attr(btn, 'value').isEmpty ? 'yes' : attr(btn, 'value');
      }
      final c = RegExp(r"confirm\('([^']*)'\)").firstMatch(attr(f, 'onsubmit'));
      form = TradeForm(fields: fields, label: sys(txt(btn)), confirm: sys(c?.group(1) ?? ''));
    }
    orders.add(TradeOrder(
      no: txt(o.querySelector('.trade_no')),
      user: txt(user),
      uid: _uidOf(attr(user, 'href')) ??
          int.tryParse(RegExp(r'UID：\s*(\d+)').firstMatch(txt(o.querySelector('.trade_user')))?.group(1) ?? ''),
      avatar: absoluteImage(attr(o.querySelector('.trade_avatar img'), 'src')),
      time: txt(o.querySelector('.trade_time')),
      offer: medals(0),
      want: medals(1),
      note: sys(txt(o.querySelector('.trade_missing'))),
      form: form,
    ));
  }

  return TradePage(
    notice: sys(txt(notice)),
    categories: cats,
    myMedals: choices('offer_mids[]'),
    allMedals: choices('want_mids[]'),
    orders: orders,
    maxOffer: strongs.length > 2 ? int.tryParse(strongs[2]) ?? 4 : 4,
    maxWant: strongs.length > 3 ? int.tryParse(strongs[3]) ?? 4 : 4,
    fee: sys(strongs.length > 4 ? strongs[4] : ''),
    formhash: attr(doc.querySelector('input[name="formhash"]'), 'value'),
    pager: parsePager(doc, current: page),
  );
}

/// 發布交易單（發布即扣發布費，取消不退）
Future<SubmitResult> createTrade({
  required String formhash,
  required List<int> offer,
  required List<int> want,
  int? targetUid,
}) async {
  // offer_mids[] 這種同名多值欄位，form 編碼要自己組
  final body = StringBuffer('formhash=${Uri.encodeQueryComponent(formhash)}&tradeop=create'
      '&target_uid=${targetUid ?? ''}&tradecreatesubmit=yes');
  for (final id in offer) {
    body.write('&${Uri.encodeQueryComponent('offer_mids[]')}=$id');
  }
  for (final id in want) {
    body.write('&${Uri.encodeQueryComponent('want_mids[]')}=$id');
  }
  final html = await Api.instance.postRaw('$_base&action=trade', body.toString(), desktop: true);
  return submitResult(html, '發布交易單');
}

/// 交易單上的表單（確認交易、取消交易…）原樣送出
Future<SubmitResult> submitTradeForm(TradeForm f) async {
  final html = await Api.instance.post('$_base&action=trade', f.fields, desktop: true);
  return submitResult(html, f.label.isEmpty ? '操作' : f.label);
}

// ── 排行榜 ────────────────────────────────────────────

class MedalRankRow {
  const MedalRankRow({required this.rank, required this.user, this.uid, this.avatar = '', this.count = '', this.reward = '', this.claim = ''});
  final String rank;
  final String user;
  final int? uid;
  final String avatar;
  final String count;
  final String reward;
  final String claim;
}

class MedalRankSection {
  const MedalRankSection({required this.title, required this.rows});
  final String title;
  final List<MedalRankRow> rows;
}

Future<List<MedalRankSection>> fetchMedalRank() async =>
    parseMedalRank(toDoc(await Api.instance.get(medalUrl(MedalTab.rank), desktop: true)));

List<MedalRankSection> parseMedalRank(dom.Document doc) => [
      for (final box in doc.querySelectorAll('.paihang'))
        MedalRankSection(
          title: sys(txt(box.querySelector('.biaoti'))),
          rows: [
            for (final li in box.querySelectorAll('ul li'))
              if (!li.classes.contains('tou'))
                MedalRankRow(
                  rank: txt(li.querySelector('.sx')),
                  user: txt(li.querySelector('.user a.xi2')),
                  uid: paramInt(attr(li.querySelector('.user a.xi2'), 'href'), 'uid'),
                  avatar: absoluteImage(attr(li.querySelector('.user img'), 'src')),
                  count: txt(li.querySelector('.count')),
                  reward: sys(txt(li.querySelector('.jiangli'))),
                  claim: sys(txt(li.querySelector('.lingqu'))),
                ),
          ],
        ),
    ];

int? _uidOf(String href) =>
    paramInt(href.replaceAll('&amp;', '&'), 'uid') ??
    int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(href)?.group(1) ?? '');
