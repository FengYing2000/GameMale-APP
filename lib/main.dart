import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gm_api/http.dart';
import 'app.dart';
import 'platform_bindings.dart';
import 'services/cjk_font_stub.dart'
    if (dart.library.js_interop) 'services/cjk_font.dart';
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

  // 網頁版要先把中文字體載進來才畫第一幀。CanvasKit 不用系統字體，
  // 少了這步第一幀會是一整片方格打叉，等 gstatic 的後備字體抓回來才變正常。
  // index.html 有 preload，所以這裡通常不會真的多等。原生版是空的。
  await loadCjkFont();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(const GameMaleApp());
}
