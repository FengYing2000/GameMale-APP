import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'api/parse.dart' as parse;
import 'i18n/s2t.dart';
import 'store/session.dart';
import 'store/settings.dart';
import 'theme.dart';
import 'ui/pages/forum_page.dart';
import 'ui/pages/guide_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/me_page.dart';
import 'ui/pages/messages_page.dart';
import 'ui/pages/my_list_page.dart';
import 'ui/pages/new_thread_page.dart';
import 'ui/pages/notice_page.dart';
import 'ui/pages/pm_chat_page.dart';
import 'ui/pages/profile_page.dart';
import 'ui/pages/reply_page.dart';
import 'ui/pages/search_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/sign_page.dart';
import 'ui/pages/thread_page.dart';

class GameMaleApp extends StatefulWidget {
  const GameMaleApp({super.key});

  @override
  State<GameMaleApp> createState() => _GameMaleAppState();
}

class _GameMaleAppState extends State<GameMaleApp> {
  late final SessionStore _session;
  late final SettingsStore _settings;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _session = SessionStore();
    _settings = SettingsStore();
    _router = _buildRouter(_session);
    _boot();
  }

  Future<void> _boot() async {
    await S2T.instance.load();
    await _settings.load();
    _applyLang();
    _settings.addListener(_applyLang);
    await _session.restore();
  }

  /// 語言設定改變時，解析層要跟著換，並重建畫面讓既有內容重新轉換
  void _applyLang() {
    final want = _settings.toTraditional;
    if (parse.convertToTraditional != want) {
      parse.convertToTraditional = want;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_applyLang);
    _session.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider.value(value: _settings),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, settings, _) => MaterialApp.router(
          title: 'GameMale',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: settings.themeMode,
          routerConfig: _router,
        ),
      ),
    );
  }
}

GoRouter _buildRouter(SessionStore session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      // 還沒問過伺服器前不要跳轉，否則會閃一下登入頁
      if (!session.ready) return null;
      final atLogin = state.matchedLocation == '/login';
      if (!session.loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginPage()),
      GoRoute(path: '/f/:fid/post', builder: (c, s) => NewThreadPage(fid: _int(s, 'fid'))),
      GoRoute(path: '/f/:fid', builder: (c, s) => ForumPage(fid: _int(s, 'fid'))),
      GoRoute(
        path: '/t/:tid/reply',
        builder: (c, s) => ReplyPage(
          tid: _int(s, 'tid'),
          fid: int.tryParse(s.uri.queryParameters['fid'] ?? '') ?? 0,
          page: int.tryParse(s.uri.queryParameters['page'] ?? '') ?? 1,
          repquote: s.uri.queryParameters['repquote'] ?? '',
          to: s.uri.queryParameters['to'] ?? '',
        ),
      ),
      GoRoute(path: '/t/:tid', builder: (c, s) => ThreadPage(tid: _int(s, 'tid'))),
      GoRoute(path: '/notice', builder: (c, s) => const NoticePage()),
      GoRoute(path: '/pm/:touid', builder: (c, s) => PmChatPage(touid: _int(s, 'touid'))),
      GoRoute(path: '/u/:uid', builder: (c, s) => ProfilePage(uid: _int(s, 'uid'))),
      GoRoute(
        path: '/my/:type',
        builder: (c, s) => MyListPage(type: s.pathParameters['type'] ?? 'thread'),
      ),
      GoRoute(path: '/sign', builder: (c, s) => const SignPage()),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Scaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/guide', builder: (c, s) => const GuidePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/search', builder: (c, s) => const SearchPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/msg', builder: (c, s) => const MessagesPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (c, s) => const MePage())]),
        ],
      ),
    ],
  );
}

int _int(GoRouterState s, String key) => int.tryParse(s.pathParameters[key] ?? '') ?? 0;

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.shell});
  final StatefulNavigationShell shell;

  static const _dest = [
    NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: '首頁'),
    NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: '導讀'),
    NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: '搜尋'),
    NavigationDestination(icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail), label: '訊息'),
    NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        destinations: _dest,
        // 再點一次目前分頁 = 回到該分頁的最上層
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
