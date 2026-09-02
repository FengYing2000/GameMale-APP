import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gm_api/http.dart';
import 'app.dart';
import 'platform_bindings.dart';
import 'services/url_strategy_stub.dart'
    if (dart.library.js_interop) 'services/url_strategy_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 網頁版的返回手勢設定（保留瀏覽器歷史，見該函式說明）。
  // Flutter 這邊不做頁面轉場（theme.dart），返回交給 iOS 原生滑動。
  configureWebUrlStrategy();

  // gm_api 是純 Dart 的，path_provider/rootBundle 要從這裡接上去
  await installFlutterBindings();
  await Api.instance.init();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(const GameMaleApp());
}
