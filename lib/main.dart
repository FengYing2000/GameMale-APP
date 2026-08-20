import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/http.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // cookie jar 要先備妥，否則首次請求會漏掉登入狀態
  await Api.instance.init();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(const GameMaleApp());
}
