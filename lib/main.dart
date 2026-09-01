import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gm_api/http.dart';
import 'app.dart';
import 'platform_bindings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // gm_api 是純 Dart 的，path_provider/rootBundle 要從這裡接上去
  await installFlutterBindings();
  await Api.instance.init();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(const GameMaleApp());
}
