// 拿真實帖子 HTML 餵給 PostBody，確認 flutter_widget_from_html 不會在
// 論壇那些手工拼出來的巢狀標籤上爆掉，而且文字/圖片/spoiler 都有真的畫出來。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/api/discuz.dart' as api;
import 'package:gamemale/api/models.dart';
import 'package:gamemale/api/parse.dart';
import 'package:gamemale/ui/widgets/post_body.dart';
import 'package:gamemale/ui/widgets/state_box.dart';
import 'package:gamemale/store/settings.dart';
import 'package:gamemale/ui/widgets/thread_tile.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => SettingsStore(),
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  final threadFile = File('test/fixtures/thread.html');
  final forumFile = File('test/fixtures/forum.html');

  group('PostBody 渲染真實帖子', () {
    if (!threadFile.existsSync()) return;
    final thread = api.parseThread(toDoc(threadFile.readAsStringSync()), 129896);

    testWidgets('每一樓都能建構且不丟例外', (tester) async {
      for (final post in thread.posts) {
        await tester.pumpWidget(_wrap(PostBody(post.html)));
        expect(tester.takeException(), isNull, reason: '第 ${post.floor} 樓渲染失敗');
      }
    });

    testWidgets('樓主的長文有畫出文字', (tester) async {
      await tester.pumpWidget(_wrap(PostBody(thread.posts.first.html)));
      expect(tester.takeException(), isNull);
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('spoiler 畫成可展開區塊', (tester) async {
      final withSpoiler =
          thread.posts.firstWhere((p) => p.html.contains('data-spoiler'));
      await tester.pumpWidget(_wrap(PostBody(withSpoiler.html)));
      expect(tester.takeException(), isNull);
      expect(find.byType(ExpansionTile), findsWidgets);
    });

    testWidgets('含圖片的樓層有建立圖片元件', (tester) async {
      final withImg = thread.posts.firstWhere((p) => p.html.contains('post-img'));
      await tester.pumpWidget(_wrap(PostBody(withImg.html)));
      expect(tester.takeException(), isNull);
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('簽名檔也能渲染', (tester) async {
      final sigs = thread.posts.where((p) => p.signature.isNotEmpty);
      expect(sigs, isNotEmpty, reason: '樣本裡應該要有簽名檔');
      for (final p in sigs) {
        await tester.pumpWidget(_wrap(PostBody(p.signature)));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('列表元件', () {
    if (!forumFile.existsSync()) return;
    final list = api.parseThreadList(toDoc(forumFile.readAsStringSync()));

    testWidgets('主題列表整批渲染', (tester) async {
      await tester.pumpWidget(_wrap(ThreadListCard(list: list)));
      expect(tester.takeException(), isNull);
      expect(find.byType(ThreadTile), findsWidgets);
    });

    testWidgets('標題與作者有出現在畫面上', (tester) async {
      final one = list.first;
      await tester.pumpWidget(_wrap(ThreadListCard(list: [one])));
      expect(tester.takeException(), isNull);
      expect(find.textContaining(one.author), findsWidgets);
    });

    testWidgets('收藏模式顯示取消收藏按鈕', (tester) async {
      var removed = false;
      await tester.pumpWidget(_wrap(ThreadListCard(
        list: [const ThreadItem(tid: 1, title: '測試', favid: 99)],
        onRemove: (_) => removed = true,
      )));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消收藏'));
      expect(removed, isTrue);
    });
  });

  group('狀態元件', () {
    testWidgets('載入中顯示轉圈', (tester) async {
      await tester.pumpWidget(_wrap(StateBox(loading: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('錯誤顯示訊息與重試', (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(
        StateBox(error: '連線失敗', onRetry: () => retried = true),
      ));
      expect(find.text('連線失敗'), findsOneWidget);
      await tester.tap(find.text('重試'));
      expect(retried, isTrue);
    });

    testWidgets('空清單顯示自訂文字', (tester) async {
      await tester.pumpWidget(_wrap(StateBox(empty: true, emptyText: '沒有私訊')));
      expect(find.text('沒有私訊'), findsOneWidget);
    });

    test('maybe 在無狀態時回傳 null', () {
      expect(StateBox.maybe(loading: false), isNull);
      expect(StateBox.maybe(loading: true), isNotNull);
    });
  });
}
