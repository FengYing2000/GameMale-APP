// 把每一頁實際 pump 起來，確認 build 不會丟例外。
//
// 測試環境的 HttpClient 一律回 400，所以每頁都會走進錯誤分支 ——
// 這正好順便驗證「論壇連不上時 App 不會白畫面或崩潰」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/store/history.dart';
import 'package:gamemale/store/session.dart';
import 'package:gamemale/store/settings.dart';
import 'package:gamemale/ui/pages/edit_post_page.dart';
import 'package:gamemale/ui/pages/forum_page.dart';
import 'package:gamemale/ui/pages/guide_page.dart';
import 'package:gamemale/ui/pages/history_page.dart';
import 'package:gamemale/ui/pages/home_page.dart';
import 'package:gamemale/ui/pages/login_page.dart';
import 'package:gamemale/ui/pages/me_page.dart';
import 'package:gamemale/ui/pages/messages_page.dart';
import 'package:gamemale/ui/pages/my_list_page.dart';
import 'package:gamemale/ui/pages/new_thread_page.dart';
import 'package:gamemale/ui/pages/notice_page.dart';
import 'package:gamemale/ui/pages/pm_chat_page.dart';
import 'package:gamemale/ui/pages/profile_page.dart';
import 'package:gamemale/ui/pages/reply_page.dart';
import 'package:gamemale/ui/pages/search_page.dart';
import 'package:gamemale/ui/pages/settings_page.dart';
import 'package:gamemale/ui/pages/space_page.dart';
import 'package:gamemale/ui/pages/sign_page.dart';
import 'package:gamemale/ui/pages/thread_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget page) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionStore()),
        ChangeNotifierProvider(create: (_) => SettingsStore()),
        ChangeNotifierProvider(create: (_) => ReplyHistory()),
      ],
      child: MaterialApp(home: page),
    );

/// 建立頁面 → 等非同步失敗回來 → 確認整段過程沒有未捕捉的例外
Future<void> _smoke(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  expect(tester.takeException(), isNull, reason: '首次 build 就爆了');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull, reason: '非同步回來之後爆了');
  expect(find.byType(Scaffold), findsWidgets);
}


void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'GameMale',
      packageName: 'tw.xingkong.gamemale',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  final pages = <String, Widget>{
    '首頁': const HomePage(),
    '導讀': const GuidePage(),
    '搜尋': const SearchPage(),
    '訊息': const MessagesPage(),
    '我的': const MePage(),
    '板塊': const ForumPage(fid: 57),
    '帖子': const ThreadPage(tid: 129896),
    '回覆': const ReplyPage(tid: 129896, fid: 57),
    '發新主題': const NewThreadPage(fid: 57),
    '通知': const NoticePage(),
    '私訊對話': const PmChatPage(touid: 1),
    '個人資料': const ProfilePage(uid: 733814),
    '個人空間': const SpacePage(uid: 733814),
    '回帖紀錄': const HistoryPage(),
    '我的收藏': const MyListPage(type: 'favorite'),
    '我的主題': const MyListPage(type: 'thread'),
    '簽到': const SignPage(),
    '設定': const SettingsPage(),
    '編輯帖子': const EditPostPage(fid: 150, tid: 1, pid: 1),
    '登入': const LoginPage(),
  };

  pages.forEach((name, page) {
    testWidgets('$name 頁能建構且離線時不崩潰', (tester) async {
      await _smoke(tester, page);
    });
  });

  testWidgets('連不上論壇時顯示錯誤與重試，而不是空白', (tester) async {
    // pump 只推進假時鐘，真正的網路 IO 要放進 runAsync 才會跑完
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(const GuidePage()));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('重試'), findsOneWidget, reason: '請求失敗後應該要顯示重試按鈕');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '失敗後不該還卡在轉圈');
  });

  testWidgets('BBCode 快捷鍵：有選取時包住選取內容', (tester) async {
    await tester.pumpWidget(_host(const ReplyPage(tid: 1, fid: 1)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.enterText(field, '測試內容');
    await tester.pump();

    // enterText 之後游標在結尾且沒有選取範圍，這裡手動選起來
    final ctrl = tester.widget<TextField>(field).controller!;
    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();

    await tester.tap(find.text('B'));
    await tester.pump();

    expect(ctrl.text, '[b]測試內容[/b]');
    expect(tester.takeException(), isNull);
  });

  testWidgets('BBCode 快捷鍵：沒選取時在游標處插入空標籤', (tester) async {
    await tester.pumpWidget(_host(const ReplyPage(tid: 1, fid: 1)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.enterText(field, '哈囉');
    await tester.pump();

    await tester.tap(find.text('圖片'));
    await tester.pump();

    final ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, '哈囉[img][/img]');
    // 游標應該停在標籤中間，直接就能打字
    expect(ctrl.selection.baseOffset, '哈囉[img]'.length);
    expect(tester.takeException(), isNull);
  });

}
