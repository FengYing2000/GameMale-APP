import 'dart:convert';

import 'package:html/dom.dart' as dom;

import 'discuz.dart' show unwrapAjax;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 你畫我猜（viewui_draw）：大廳、猜題／吐槽、我的紀錄、排行榜。
///
/// 「我來畫」（ac=draw）的送出方式還沒看過（抓樣本那天創作次數已用完），這裡先不做。
const _base = 'plugin.php?id=viewui_draw';

class DrawItem {
  const DrawItem({
    required this.id,
    this.topic = '',
    this.image = '',
    this.ongoing = false,
    this.answer = '',
    this.lastSay = '',
    this.participants = '',
  });
  final int id;

  /// 主題（水果）
  final String topic;
  final String image;
  final bool ongoing;

  /// 已完結的才有：答案
  final String answer;

  /// 最新一則發言
  final String lastSay;

  /// 「1人参与」
  final String participants;
}

class DrawLobby {
  const DrawLobby({this.items = const [], this.pager = const PageInfo(), this.message});
  final List<DrawItem> items;
  final PageInfo pager;
  final String? message;
}

/// [status]：0 全部、1 進行中、2 已完結
Future<DrawLobby> fetchDrawLobby({int status = 0, int page = 1}) async {
  final q = StringBuffer('$_base&mod=list');
  if (status > 0) q.write('&status=$status');
  if (page > 1) q.write('&page=$page');
  return parseDrawLobby(toDoc(await Api.instance.get(q.toString(), desktop: true)), page: page);
}

String _bgUrl(dom.Element? el) =>
    absoluteImage(RegExp(r"url\(\s*'?([^')]+)'?\s*\)").firstMatch(attr(el, 'style'))?.group(1) ?? '');

DrawLobby parseDrawLobby(dom.Document doc, {int page = 1}) {
  final items = <DrawItem>[];
  for (final li in doc.querySelectorAll('.piclist li')) {
    final id = int.tryParse(RegExp(r'drawid=(\d+)').firstMatch(attr(li, 'onclick'))?.group(1) ?? '');
    if (id == null) continue;
    items.add(DrawItem(
      id: id,
      topic: sys(txt(li.querySelector('.info .smr'))),
      image: _bgUrl(li.querySelector('.img')),
      ongoing: li.querySelector('.status.ing') != null,
      answer: sys(txt(li.querySelector('.result .txt')).replaceFirst(RegExp(r'^答案[:：]'), '')),
      lastSay: txt(li.querySelector('.say .content')),
      participants: sys(txt(li.querySelector('.info .r'))),
    ));
  }
  return DrawLobby(
    items: items,
    pager: parsePager(doc, current: page),
    message: items.isEmpty ? noticeMessage(doc) : null,
  );
}

/// 猜題彈窗裡的一則（竟猜、吐槽、系統提醒、日期分隔）
class DrawComment {
  const DrawComment({
    this.user = '',
    this.uid,
    this.avatar = '',
    this.text = '',
    this.correct,
    this.guess = false,
    this.system = false,
    this.date = false,
  });
  final String user;
  final int? uid;
  final String avatar;
  final String text;

  /// 竟猜的對錯（吐槽是 null）
  final bool? correct;

  /// 是竟猜（「XX猜:」）還是吐槽（「XX说:」）
  final bool guess;

  /// 系統提醒（當前畫作已結束…）
  final bool system;

  /// 日期分隔列
  final bool date;
}

class DrawDetail {
  const DrawDetail({
    required this.id,
    this.title = '',
    this.tip = '',
    this.image = '',
    this.comments = const [],
    this.answered = false,
    this.leftThis = 0,
    this.leftToday = 0,
    this.authorUid,
    this.formhash = '',
    this.message,
  });
  final int id;

  /// 「[已完结] 主题: 水果」
  final String title;

  /// 「正确答案:苹果」或提示
  final String tip;
  final String image;
  final List<DrawComment> comments;

  /// 已經有人猜中（只能吐槽）
  final bool answered;

  /// 這幅畫我還能猜幾次
  final int leftThis;

  /// 今天還能猜幾次
  final int leftToday;

  /// 作者（作者不能猜自己的畫）
  final int? authorUid;
  final String formhash;
  final String? message;
}

Future<DrawDetail> fetchDrawDetail(int id) async {
  final xml = await Api.instance.get(
      '$_base&mod=list&ac=guess&drawid=$id&inajax=1&ajaxtarget=fwin_content_viewui_draw_guess',
      desktop: true);
  return parseDrawDetail(unwrapAjax(xml), id: id);
}

DrawDetail parseDrawDetail(String html, {required int id}) {
  final doc = toDoc(html);
  String jsVar(String name) =>
      RegExp('var\\s+$name\\s*=\\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';
  final comments = <DrawComment>[];
  for (final itm in doc.querySelectorAll('#joinlist .itm')) {
    if (itm.classes.contains('time')) {
      comments.add(DrawComment(text: txt(itm), date: true));
      continue;
    }
    if (itm.classes.contains('system')) {
      comments.add(DrawComment(text: sys(txt(itm)), system: true));
      continue;
    }
    final nm = txt(itm.querySelector('.nm'));
    final say = itm.querySelector('.say');
    final img = attr(say?.querySelector('img'), 'src');
    comments.add(DrawComment(
      user: nm.replaceFirst(RegExp(r'[猜说說][:：]?\s*$'), ''),
      uid: paramInt(attr(itm.querySelector('a.avatar'), 'href').replaceAll('&amp;', '&'), 'uid'),
      avatar: absoluteImage(attr(itm.querySelector('.avatar img'), 'src')),
      text: txt(say),
      guess: nm.contains('猜'),
      correct: img.contains('right') ? true : (img.contains('error') ? false : null),
    ));
  }
  final author = RegExp(r'discuz_uid\s*==\s*"(\d+)"').firstMatch(html)?.group(1);
  return DrawDetail(
    id: id,
    title: sys(txt(doc.querySelector('h3 .tt'))),
    tip: sys(txt(doc.querySelector('#tips'))),
    image: _bgUrl(doc.querySelector('.pic div[style*="url"]')),
    comments: comments,
    answered: jsVar('isanswer') == '1',
    leftThis: int.tryParse(jsVar('drawcanguess')) ?? 0,
    leftToday: int.tryParse(jsVar('allcanguess')) ?? 0,
    authorUid: int.tryParse(author ?? ''),
    formhash: RegExp(r'formhash:\s*"([0-9a-f]+)"').firstMatch(html)?.group(1) ??
        (Api.instance.formhash ?? ''),
    message: doc.querySelector('#joinlist') == null ? noticeMessage(doc) : null,
  );
}

class DrawGuessResult {
  const DrawGuessResult({required this.ok, this.message = '', this.correct = false, this.answer = '', this.reward = '', this.leftThis, this.leftToday});
  final bool ok;
  final String message;

  /// 猜中了
  final bool correct;
  final String answer;

  /// 「5 金币」
  final String reward;
  final int? leftThis;
  final int? leftToday;
}

/// 送出竟猜（[guess]＝true）或吐槽
Future<DrawGuessResult> sendDrawGuess(DrawDetail d, String text, {required bool guess}) async {
  final body = await Api.instance.post('$_base&mod=api&ac=addguess', {
    'fid': '${d.id}',
    'guessmod': guess ? '1' : '2',
    // 網頁是 encodeURI 之後再送（伺服器會解一次），照做
    'message': Uri.encodeFull(text),
    'formhash': d.formhash,
  }, desktop: true);
  return parseGuessResult(body);
}

DrawGuessResult parseGuessResult(String body) {
  Map<String, dynamic>? j;
  try {
    final v = json.decode(body.trim());
    if (v is Map<String, dynamic>) j = v;
  } catch (_) {}
  if (j == null) {
    final t = sys(txt(toDoc(body).body));
    return DrawGuessResult(ok: false, message: t.isEmpty ? '送出失敗' : t);
  }
  final ok = '${j['code']}' == 'SUCCEED';
  final data = j['data'] is Map ? (j['data'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
  final correct = '${data['isanswer']}' == '1' && '${data['result']}' == '1';
  final n = int.tryParse('${data['guessextcreditsnum'] ?? ''}') ?? 0;
  return DrawGuessResult(
    ok: ok,
    message: sys('${j['msg'] ?? j['message'] ?? (ok ? '已送出' : '送出失敗')}'),
    correct: correct,
    answer: sys('${data['answer'] ?? ''}'),
    reward: n > 0 ? sys('$n ${data['guessextcredits'] ?? ''}'.trim()) : '',
    leftThis: int.tryParse('${data['drawcanguess'] ?? ''}'),
    leftToday: int.tryParse('${data['allcanguess'] ?? ''}'),
  );
}

// ── 我的紀錄、排行榜 ───────────────────────────────────

class DrawLogRow {
  const DrawLogRow({this.drawId, this.topic = '', this.image = '', this.type = '', this.content = '', this.time = '', this.correct});
  final int? drawId;
  final String topic;
  final String image;
  final String type;
  final String content;
  final String time;
  final bool? correct;
}

class DrawLog {
  const DrawLog({this.stats = const [], this.today = const [], this.rows = const [], this.pager = const PageInfo()});

  /// (數字, 標籤)：累計參與、累計猜中、正確率
  final List<(String, String)> stats;

  /// 今日竟猜、今日還可競猜…
  final List<String> today;
  final List<DrawLogRow> rows;
  final PageInfo pager;
}

/// [created]＝我創作的；否則我參與的
Future<DrawLog> fetchDrawLog({bool created = false, int page = 1}) async {
  final q = StringBuffer('$_base&mod=log');
  if (created) q.write('&ac=draw');
  if (page > 1) q.write('&page=$page');
  return parseDrawLog(toDoc(await Api.instance.get(q.toString(), desktop: true)), page: page);
}

DrawLog parseDrawLog(dom.Document doc, {int page = 1}) {
  final rows = <DrawLogRow>[];
  for (final tr in doc.querySelectorAll('table.tablelist tr')) {
    if (tr.classes.contains('tp')) continue;
    final tds = tr.querySelectorAll('td');
    if (tds.length < 4) continue;
    final link = tds[0].querySelector('a');
    final resultImg = attr(tr.querySelector('img[src*="right"], img[src*="error"]'), 'src');
    rows.add(DrawLogRow(
      drawId: paramInt(attr(link, 'href').replaceAll('&amp;', '&'), 'opendrawid'),
      topic: sys(txt(tds[0])),
      image: absoluteImage(attr(tds[1].querySelector('img'), 'src')),
      type: sys(txt(tds.length > 2 ? tds[2] : null)),
      content: txt(tds.length > 3 ? tds[3] : null),
      time: txt(tds.length > 4 ? tds[4] : null),
      correct: resultImg.contains('right') ? true : (resultImg.contains('error') ? false : null),
    ));
  }
  return DrawLog(
    stats: [
      for (final n in doc.querySelectorAll('.userinfo .info .num'))
        (txt(n.querySelector('cite')), sys(txt(n.querySelector('span')))),
    ],
    today: [
      for (final p in doc.querySelectorAll('.userinfo .abt p'))
        if (!p.classes.contains('name') && txt(p).isNotEmpty) sys(txt(p)),
    ],
    rows: rows,
    pager: parsePager(doc, current: page),
  );
}

class DrawRankRow {
  const DrawRankRow({required this.rank, required this.user, this.uid, this.avatar = '', this.detail = ''});
  final String rank;
  final String user;
  final int? uid;
  final String avatar;
  final String detail;
}

/// [draw]＝繪畫榜；否則竟猜榜。回傳 (說明, 名單)
Future<(String, List<DrawRankRow>)> fetchDrawRank({bool draw = false}) async {
  final html = await Api.instance.get('$_base&mod=rank&ac=${draw ? 'draw' : 'guess'}', desktop: true);
  return parseDrawRank(toDoc(html));
}

(String, List<DrawRankRow>) parseDrawRank(dom.Document doc) {
  final rows = <DrawRankRow>[];
  for (final li in doc.querySelectorAll('.ranklist li')) {
    final numEl = li.querySelector('.num');
    final img = numEl?.querySelector('img');
    final avatar = attr(li.querySelector('.avatar img'), 'src');
    rows.add(DrawRankRow(
      rank: img != null ? attr(img, 'alt') : txt(numEl),
      user: txt(li.querySelector('.name')),
      uid: paramInt(avatar.replaceAll('&amp;', '&'), 'uid'),
      avatar: absoluteImage(avatar),
      detail: sys(li.querySelectorAll('.abt p').skip(1).map(txt).join(' ')),
    ));
  }
  return (sys(txt(doc.querySelector('.ranktip'))), rows);
}
