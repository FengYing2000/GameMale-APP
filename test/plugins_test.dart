// 論壇功能（外掛頁）的解析測試。樣本在 test/fixtures/plugins/（登入後抓的，
// 含帳號資料所以不進版控）；沒有樣本的環境（CI）會自動略過。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:gm_api/credit.dart' as credit;
import 'package:gm_api/decor_shop.dart' as decor;
import 'package:gm_api/draw.dart' as draw;
import 'package:gm_api/lottery.dart' as lottery;
import 'package:gm_api/magic_shop.dart' as magic;
import 'package:gm_api/medal.dart' as medal;
import 'package:gm_api/popup.dart' as popup;
import 'package:gm_api/task.dart' as task;
import 'package:gm_api/parse.dart';

dom.Document? _doc(String name) {
  final f = File('test/fixtures/plugins/$name.html');
  if (!f.existsSync()) return null;
  return toDoc(f.readAsStringSync());
}

String? _raw(String name) {
  final f = File('test/fixtures/plugins/$name.html');
  return f.existsSync() ? f.readAsStringSync() : null;
}

void main() {
  // 測試裡不做繁簡轉換，比對原文
  setUpAll(() => uiTraditional = false);

  group('勳章商城', () {
    test('分類、勳章、狀態、價格與庫存', () {
      final doc = _doc('m_fid16');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      expect(p.categories.length, greaterThan(10));
      expect(p.categories.where((c) => c.current), hasLength(1));
      expect(p.idField, 'medalid');
      expect(p.formhash, isNotEmpty);

      final buyable = p.items.firstWhere((m) => m.actions.any((a) => a.kind == 'goumai'));
      final a = buyable.actions.firstWhere((a) => a.kind == 'goumai');
      expect(a.id, buyable.id);
      expect(a.arg, isNotEmpty, reason: '購買價格（旅程 10）要帶出來給確認框');
      expect(buyable.price, isNotEmpty);
      expect(buyable.stock, isNotEmpty);
      expect(buyable.image, startsWith('http'));

      // 結束購買／無貨的狀態字
      expect(p.items.map((m) => m.status), anyElement(anyOf('结束购买', '无货啦！', '不可购买！', '已拥有')));
    });

    test('領取條件與可回收旗標', () {
      final doc = _doc('m_fid16');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      final withCond = p.items.firstWhere((m) => m.condition.isNotEmpty);
      expect(withCond.condition, contains('领取条件'));
      expect(p.items.map((m) => m.recyclable), contains(isNotNull));
    });

    test('頁尾勳章紀錄與分頁', () {
      final doc = _doc('medalshop');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      expect(p.records, isNotEmpty);
      expect(p.records.first.medal, isNotEmpty);
      expect(p.records.first.uid, isNotNull);
      expect(p.pager.total, greaterThan(1));
    });
  });

  group('我的勳章', () {
    test('統計、編號欄位、回收／寄售／升級／續期、顯示開關', () {
      final doc = _doc('mymedal');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      expect(p.idField, 'userMedalid');
      expect(p.stats, isNotEmpty);
      expect(p.stats.first.limit, isNotEmpty);
      final kinds = {for (final m in p.items) for (final a in m.actions) a.kind};
      expect(kinds, containsAll(['huishou', 'jishou', 'UPLV']));
      final m = p.items.firstWhere((m) => m.actions.any((a) => a.kind == 'jishou'));
      expect(m.userMedalId, isNotNull);
      expect(m.shown, isNotNull);
      final js = m.actions.firstWhere((a) => a.kind == 'jishou');
      expect(int.tryParse(js.arg), isNotNull, reason: '寄售上限是數字');
      expect(p.items.any((m) => m.effects.isNotEmpty), isTrue, reason: '屬性加成（發帖 血液 +1）');
    });
  });

  group('榮譽／獎勵／二手市場', () {
    test('榮譽勳章有領取鈕', () {
      final doc = _doc('m_rongyu');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      expect(p.items.expand((m) => m.actions).map((a) => a.kind), contains('lingqu'));
    });

    test('二手市場：寄售單號、賣家、價格', () {
      final doc = _doc('m_jishou');
      if (doc == null) return;
      final p = medal.parseMedalPage(doc);
      final m = p.items.first;
      expect(m.actions.single.kind, 'goumaijishou');
      expect(m.actions.single.id, m.id, reason: 'tip 的 er 編號＝寄售單號');
      expect(m.infoOf('寄售用户'), isNotEmpty);
      expect(m.price, contains('金币'));
    });
  });

  group('組合、交易角、排行', () {
    test('勳章組合', () {
      final doc = _doc('m_combo');
      if (doc == null) return;
      final c = medal.parseMedalCombos(doc);
      expect(c.combos.length, greaterThan(10));
      expect(c.combos.any((x) => x.active), isTrue);
      expect(c.combos.first.medals, isNotEmpty);
      expect(c.summary, isNotEmpty);
    });

    test('交易角：可提供／可索要的勳章、交易單與確認表單', () {
      final doc = _doc('m_trade');
      if (doc == null) return;
      final t = medal.parseTradePage(doc);
      expect(t.myMedals, isNotEmpty);
      expect(t.allMedals.length, greaterThan(t.myMedals.length));
      expect(t.maxOffer, 4);
      expect(t.fee, contains('金币'));
      expect(t.orders, isNotEmpty);
      final withForm = t.orders.firstWhere((o) => o.form != null);
      expect(withForm.form!.fields['tradeop'], 'accept');
      expect(withForm.form!.fields['tradeid'], isNotEmpty);
      expect(withForm.form!.fields['tradeacceptsubmit'], 'yes');
      expect(withForm.form!.confirm, isNotEmpty);
      expect(t.orders.any((o) => o.note.isNotEmpty), isTrue);
      expect(t.categories, isNotEmpty);
    });

    test('排行榜', () {
      final doc = _doc('m_paihang');
      if (doc == null) return;
      final r = medal.parseMedalRank(doc);
      expect(r, isNotEmpty);
      expect(r.first.rows.first.rank, '1');
      expect(r.first.rows.first.uid, isNotNull);
    });
  });

  group('道具', () {
    test('商店：名稱、價格、購買／贈送彈窗、缺貨', () {
      final doc = _doc('magic');
      if (doc == null) return;
      final p = magic.parseMagicShop(doc);
      expect(p.items.length, greaterThan(3));
      expect(p.capacity, contains('/'));
      expect(p.balance, contains('金币'));
      expect(p.balance, isNot(contains('兑换')));
      final buyable = p.items.firstWhere((i) => i.actions.isNotEmpty);
      expect(buyable.actions.first.$2, contains('operation=buy'));
      expect(buyable.price, contains('金币'));
      expect(p.items.any((i) => i.soldOut.isNotEmpty), isTrue);
    });
    test('我的道具：數量與贈送／丟棄', () {
      final doc = _doc('mg_box');
      if (doc == null) return;
      final p = magic.parseMagicShop(doc);
      expect(p.items, isNotEmpty);
      expect(p.items.first.amount, contains('数量'));
      expect(p.items.first.actions.map((a) => a.$2).join(), contains('operation=give'));
    });
    test('記錄表格', () {
      final doc = _doc('mg_log');
      if (doc == null) return;
      final t = magic.parseTable(doc.querySelector('table.dt'));
      expect(t.headers, contains('名称'));
      expect(t.rows, isNotEmpty);
    });
    test('道具購買彈窗解析成原生表單', () {
      final f = File('test/fixtures/magic_buy.xml');
      if (!f.existsSync()) return;
      final inner = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(f.readAsStringSync())?.group(1) ?? '';
      final r = popup.parsePopup(inner);
      expect(r.form, isNotNull);
      expect(r.form!.hidden, contains('formhash'));
      expect(r.form!.action, isNotEmpty);
    });
  });

  group('積分兌換（血液祭獻）', () {
    test('餘額、可換的積分、稅率與所需數量', () {
      final doc = _doc('blood');
      if (doc == null) return;
      final p = credit.parseCreditExchange(doc);
      expect(p.balances.map((b) => b.name), containsAll(['旅程', '金币', '血液']));
      expect(p.to.map((o) => o.name), contains('旅程'));
      expect(p.from.single.name, '血液');
      expect(p.tax, closeTo(0.15, 1e-9));
      expect(p.formhash, isNotEmpty);
      final journey = p.to.firstWhere((o) => o.name == '旅程');
      // 網頁的算法：旅程 ratio 30、血液 ratio 1 → 換 1 旅程要 floor(30×1.15)＝34 血液
      expect(p.cost(journey, p.from.single, 1), 34);
      expect(p.cost(journey, p.from.single, 0), 0);
    });
    test('積分記錄', () {
      final doc = _doc('credit_log');
      if (doc == null) return;
      final t = magic.parseTable(doc.querySelector('table.dt'));
      expect(t.headers, contains('积分变更'));
      expect(t.rows.first.length, 4);
    });
  });

  group('日常卡片（抽獎）', () {
    test('獎品、每日次數與花費', () {
      final raw = _raw('card_goods');
      if (raw == null) return;
      final info = lottery.parseLottery(raw);
      expect(info.prizes, hasLength(4));
      expect(info.prizes.first.name, 'I 等卡片');
      expect(info.prizes.first.reward, contains('血液'));
      expect(info.perDay, 1);
      expect(info.cost, contains('2'));
      expect(info.image, startsWith('http'));
    });
    test('我的抽獎紀錄', () {
      final raw = _raw('card_my');
      if (raw == null) return;
      final m = lottery.parseLotteryMine(raw);
      expect(m.summary, isNotEmpty);
      expect(m.records, isNotEmpty);
      expect(m.records.first.prize, contains('等卡片'));
      expect(m.records.first.time, startsWith('20'));
    });
    test('抽獎回應：有 split＝抽到、沒有＝錯誤訊息', () {
      expect(lottery.parseDrawResult('<b>x</b>it618_split恭喜您抽到了 I 等卡片').$1, isTrue);
      final fail = lottery.parseDrawResult('今天的抽奖次数已用完');
      expect(fail.$1, isFalse);
      expect(fail.$2, contains('次数'));
    });
  });

  group('頭銜、名片、背景', () {
    test('頭銜商店：價格、期限、購買（會扣款）', () {
      final doc = _doc('buyname');
      if (doc == null) return;
      final p = decor.parseTitleShop(doc);
      expect(p.items.length, greaterThan(5));
      final a = p.items.first.actions.single;
      expect(a.url, contains('mod=buy'));
      expect(a.charges, isTrue);
      expect(p.items.first.price, contains('金币'));
      expect(p.pager.total, greaterThan(1));
    });
    test('我的稱號：佩戴／取消佩戴', () {
      final doc = _doc('bn_manage');
      if (doc == null) return;
      final p = decor.parseTitleShop(doc, mine: true);
      final labels = p.items.expand((i) => i.actions).map((a) => a.label).toSet();
      expect(labels, containsAll(['佩戴', '取消佩戴']));
      expect(p.items.first.info.map((e) => e.$1), contains('到期时间'));
    });
    test('名片商城：預覽圖、價格、天數、文字色', () {
      final doc = _doc('usercard');
      if (doc == null) return;
      final p = decor.parseCardShop(doc);
      expect(p.items, isNotEmpty);
      final c = p.items.first;
      expect(c.image, startsWith('http'));
      expect(c.price, contains('金币'));
      expect(c.duration, contains('天'));
      expect(c.actions.single.url, contains('act=buy'));
      expect(p.items.any((i) => i.textColor != null), isTrue);
    });
    test('背景商店：分類、價格、天數、購買網址帶 formhash', () {
      final doc = _doc('bgshop');
      if (doc == null) return;
      final p = decor.parseBgShop(doc);
      expect(p.categories, isNotEmpty);
      expect(p.categories.where((c) => c.$4), hasLength(1));
      final b = p.items.first;
      expect(b.price, contains('金币'));
      expect(b.duration, contains('天'));
      expect(b.actions.first.url, allOf(contains('mod=buy'), contains('formhash=')));
      expect(b.info.map((e) => e.$1), contains('大小'));
    });
    test('我的背景（空的也不出錯）', () {
      final doc = _doc('bg_my');
      if (doc == null) return;
      final p = decor.parseBgShop(doc, mine: true);
      expect(p.items, isEmpty);
      expect(p.notes, contains('暂无购买记录'));
    });
  });

  group('你畫我猜', () {
    test('大廳', () {
      final doc = _doc('draw');
      if (doc == null) return;
      final l = draw.parseDrawLobby(doc);
      expect(l.items, isNotEmpty);
      expect(l.items.first.image, contains('viewui_draw/resource'));
      expect(l.items.any((i) => i.answer.isNotEmpty), isTrue);
      expect(l.items.first.topic, isNotEmpty);
    });
    test('猜題彈窗：答案、留言、對錯', () {
      final raw = _raw('dr_guess');
      if (raw == null) return;
      final inner = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(raw)!.group(1)!;
      final d = draw.parseDrawDetail(inner, id: 125333);
      expect(d.title, contains('主题'));
      expect(d.answered, isTrue);
      expect(d.image, contains('viewui_draw/resource'));
      expect(d.comments.any((c) => c.guess && c.correct == true), isTrue);
      expect(d.comments.any((c) => c.system), isTrue);
      expect(d.formhash, isNotEmpty);
    });
    test('送出結果', () {
      final r = draw.parseGuessResult('{"code":"SUCCEED","data":{"mod":"1","isanswer":"1","result":"1",'
          '"answer":"苹果","guessextcredits":"金币","guessextcreditsnum":"5","drawcanguess":"4","allcanguess":"3"}}');
      expect(r.ok, isTrue);
      expect(r.correct, isTrue);
      expect(r.reward, '5 金币');
      expect(r.leftToday, 3);
      expect(draw.parseGuessResult('<p>请先登录</p>').ok, isFalse);
    });
    test('我的紀錄與排行', () {
      final doc = _doc('dr_log');
      if (doc == null) return;
      final log = draw.parseDrawLog(doc);
      expect(log.stats, hasLength(3));
      expect(log.rows, isNotEmpty);
      expect(log.rows.first.drawId, isNotNull);
      final rank = draw.parseDrawRank(_doc('dr_rank')!);
      expect(rank.$2.first.rank, '1');
      expect(rank.$2.first.uid, isNotNull);
    });
  });

  group('任務與回帖獎勵', () {
    test('新任務列表有申請連結', () {
      final doc = _doc('task');
      if (doc == null) return;
      final p = task.parseTaskList(doc);
      expect(p.items, isNotEmpty);
      expect(p.items.first.reward, contains('金币'));
      expect(p.items.first.actions.single.url, contains('do=apply'));
    });
    test('已完成列表', () {
      final doc = _doc('t_done');
      if (doc == null) return;
      final p = task.parseTaskList(doc);
      expect(p.items.length, greaterThan(1));
      expect(p.items.first.status, contains('完成'));
    });
    test('任務詳情：週期、說明分行、獎勵與條件', () {
      final doc = _doc('posttask');
      if (doc == null) return;
      final d = task.parseTask(doc, id: 25);
      expect(d.name, '每周发帖任务');
      expect(d.period, contains('每周'));
      expect(d.description.split('\n').length, greaterThan(5));
      expect(d.rows.map((r) => r.$1), contains('奖励'));
      expect(d.rows.map((r) => r.$1), contains('完成条件'));
      expect(d.actions.single.url, contains('do=apply'));
      expect(d.status, contains('完成于'));
    });
    test('每月回帖獎勵', () {
      final doc = _doc('replytask');
      if (doc == null) return;
      final p = task.parseReplyReward(doc);
      expect(p.boxes, hasLength(2));
      expect(p.boxes.first.reward, contains('金币'));
      expect(p.boxes.first.state, '尚未完成');
      expect(p.boxes.first.condition, contains('40'));
      expect(p.rules, isNotEmpty);
    });
  });

  test('樣本存在', () {
    // 讓人知道這一組是不是真的有跑（沒有樣本時上面全部略過）
    if (_raw('medalshop') == null) markTestSkipped('沒有外掛頁樣本');
  });
}
