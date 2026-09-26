// 論壇功能原生頁的畫面測試：用登入後抓的真實頁面樣本（test/fixtures/plugins/，
// 含帳號資料不進版控）當論壇回應，把每一頁、每個分頁、詳細資料彈窗都在手機尺寸
// 實際畫出來，確認沒有例外、沒有跑版（RenderFlex overflow 也會被當成例外）。
// 沒有樣本的環境（CI）自動略過。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/store/accounts.dart';
import 'package:gamemale/store/session.dart';
import 'package:gamemale/store/settings.dart';
import 'package:gamemale/ui/pages/tools/credit_page.dart';
import 'package:gamemale/ui/pages/tools/decor_pages.dart';
import 'package:gamemale/ui/pages/tools/draw_page.dart';
import 'package:gamemale/ui/pages/tools/lottery_page.dart';
import 'package:gamemale/ui/pages/tools/magic_page.dart';
import 'package:gamemale/ui/pages/tools/medal_page.dart';
import 'package:gamemale/ui/pages/tools/task_page.dart';
import 'package:gamemale/ui/widgets/shop_kit.dart';
import 'package:gm_api/http.dart';
import 'package:gm_api/medal.dart' show MedalTab;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dir = Directory('test/fixtures/plugins');
final _cache = <String, String>{};
final _asked = <String>[];

String _fixture(String name) =>
    _cache.putIfAbsent(name, () => File('${_dir.path}/$name.html').readAsStringSync());

/// 網址 → 樣本檔
@visibleForTesting
String routeForTest(String url) => _route(url);

String _route(String url) {
  bool has(String s) => url.contains(s);
  if (has('wodexunzhang')) {
    if (has('action=my')) return 'mymedal';
    if (has('showRongyu')) return 'm_rongyu';
    if (has('showJiangli')) return 'm_jiangli';
    if (has('showjishou')) return 'm_jishou';
    if (has('action=trade')) return 'm_trade';
    if (has('action=combo')) return 'm_combo';
    if (has('action=paihang')) return 'm_paihang';
    if (has('fid=')) return 'm_fid16';
    return 'medalshop';
  }
  if (has('mod=magic')) {
    if (has('action=mybox')) return 'mg_box';
    if (has('action=log')) return 'mg_log';
    return 'magic';
  }
  if (has('ac=credit')) return has('op=log') ? 'credit_log' : 'blood';
  if (has('it618_award')) return has('ac1=myaward') ? 'card_my' : 'card_goods';
  if (has('tshuz_buyname')) return has('mod=manage') ? 'bn_manage' : 'buyname';
  if (has('k_usercard')) return has('mod=mycard') ? 'uc_my' : 'usercard';
  if (has('tshuz_bgshop')) {
    if (has('mod=my')) return 'bg_my';
    if (has('pid=2')) return 'bg_pid2';
    return 'bgshop';
  }
  if (has('viewui_draw')) {
    if (has('ac=guess&drawid')) return 'dr_guess';
    if (has('mod=log')) return 'dr_log';
    if (has('mod=rank')) return 'dr_rank';
    return 'draw';
  }
  if (has('mod=task')) {
    if (has('id=25')) return 'posttask';
    if (has('do=view')) return 't_14';
    if (has('item=done')) return 't_done';
    return 'task';
  }
  if (has('reply_reward')) {
    if (has('code=1')) return 'rr_hist';
    if (has('code=2')) return 'rr_rank';
    return 'replytask';
  }
  return '';
}

Widget _host(Widget page) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionStore()),
        ChangeNotifierProvider(create: (_) => SettingsStore()),
        ChangeNotifierProvider(create: (ctx) => AccountsStore(ctx.read<SessionStore>())),
      ],
      child: MaterialApp(home: page),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 打開頁面 → 逐一點分頁 → 每一步都不能有例外，也不能停在「讀取失敗」
Future<void> _visit(WidgetTester tester, Widget page, {List<String> tabs = const [], bool openFirstCard = false}) async {
  await tester.pumpWidget(_host(page));
  await _settle(tester);
  expect(tester.takeException(), isNull);
  expect(find.textContaining('讀取失敗'), findsNothing);

  if (openFirstCard) {
    final card = find.byType(ItemCard);
    expect(card, findsWidgets, reason: '樣本裡應該有東西');
    await tester.tap(card.first);
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: '詳細資料彈窗爆了');
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
  }

  for (final t in tabs) {
    await tester.tap(find.widgetWithText(Tab, t).first);
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: '分頁「$t」爆了');
    expect(find.textContaining('讀取失敗'), findsNothing, reason: '分頁「$t」讀取失敗');
  }
}

void main() {
  final skip = !_dir.existsSync() ? '沒有論壇頁面樣本' : null;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    Api.browserFetch = (url, {form}) async {
      _asked.add(url);
      final name = _route(url);
      if (name.isEmpty) return '<html><body></body></html>';
      return _fixture(name);
    };
    Api.forceBrowser();
  });

  tearDownAll(() {
    Api.browserFetch = null;
    Api.resetTransport();
  });

  setUp(() => _asked.clear());

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('勳章：八個分頁與詳細資料', (tester) async {
    await phone(tester);
    await _visit(tester, const MedalPage(), openFirstCard: true);
    for (final tab in MedalTab.values) {
      await _visit(tester, MedalPage(initial: tab));
    }
  }, skip: skip != null);

  testWidgets('道具超市', (tester) async {
    await phone(tester);
    await _visit(tester, const MagicPage(), openFirstCard: true, tabs: ['熱銷', '我的道具', '記錄']);
  }, skip: skip != null);

  testWidgets('血液祭獻', (tester) async {
    await phone(tester);
    await _visit(tester, const CreditPage(), tabs: ['積分記錄']);
  }, skip: skip != null);

  testWidgets('日常卡片', (tester) async {
    await phone(tester);
    await _visit(tester, const LotteryPage(), tabs: ['我的紀錄']);
    // 絕對不能碰到會扣款的抽獎端點
    expect(_asked.where((u) => u.contains('getwapaward')), isEmpty);
  }, skip: skip != null);

  testWidgets('頭銜稱號', (tester) async {
    await phone(tester);
    await _visit(tester, const TitleShopPage(), tabs: ['我的稱號']);
    expect(_asked.where((u) => u.contains('mod=buy')), isEmpty);
  }, skip: skip != null);

  testWidgets('多彩名片', (tester) async {
    await phone(tester);
    await _visit(tester, const CardShopPage(), openFirstCard: true, tabs: ['人氣', '我的名片']);
    expect(_asked.where((u) => u.contains('act=buy')), isEmpty);
  }, skip: skip != null);

  testWidgets('背景商店', (tester) async {
    await phone(tester);
    await _visit(tester, const BgShopPage(), openFirstCard: true, tabs: ['正文背景', '我的背景']);
    expect(_asked.where((u) => u.contains('mod=buy')), isEmpty);
  }, skip: skip != null);

  testWidgets('你畫我猜：大廳、紀錄、排行、猜題頁', (tester) async {
    await phone(tester);
    await _visit(tester, const DrawPage(), tabs: ['我的紀錄', '排行榜']);
    await _visit(tester, const DrawDetailPage(id: 1));
    expect(find.text('猜答案'), findsOneWidget);
  }, skip: skip != null);

  testWidgets('熱門任務與任務詳情', (tester) async {
    await phone(tester);
    await _visit(tester, const TaskPage(), tabs: ['進行中', '已完成', '失敗']);
    await _visit(tester, const TaskDetailPage(id: 14));
    await _visit(tester, const TaskDetailPage(id: 25, title: '每週發帖獎勵'));
  }, skip: skip != null);

  testWidgets('每月回帖獎勵', (tester) async {
    await phone(tester);
    await _visit(tester, const ReplyRewardPage(), tabs: ['獎勵歷史', '達人榜']);
  }, skip: skip != null);
}
