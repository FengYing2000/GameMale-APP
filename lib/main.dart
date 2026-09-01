import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gm_api/http.dart';
import 'app.dart';
import 'platform_bindings.dart';
import 'services/url_strategy_stub.dart'
    if (dart.library.js_interop) 'services/url_strategy_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 網頁版：不要產生瀏覽器歷史，否則 iOS 的系統返回手勢會跟
  // Flutter 自己的拖曳返回打架，動畫跑兩遍
  installNoHistoryUrlStrategy();

  // gm_api 是純 Dart 的，path_provider/rootBundle 要從這裡接上去
  await installFlutterBindings();
  await Api.instance.init();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(const GameMaleApp());
}
