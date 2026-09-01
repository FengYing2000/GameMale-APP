import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/s2t.dart';

/// 把伺服器這邊的東西接到純 Dart 的 `gm_api` 上。
///
/// 跟 Flutter App 那邊的 `platform_bindings.dart` 是對稱的：同一套解析，
/// 兩邊各自注入自己的 cookie 儲存與轉換表來源。
///
/// **要在任何 Api 呼叫之前先跑一次。**
Future<void> installServerBindings({
  String dataDir = '/data',
  String assetDir = '/srv/assets',
}) async {
  Api.cookieJarFactory = () =>
      PersistCookieJar(storage: FileStorage('$dataDir/cookies'));

  S2T.assetLoader = (path) async {
    // gm_api 傳進來的是 Flutter 的資產路徑（assets/s2t.json），
    // 這裡只取檔名，對到伺服器自己的資料夾
    final name = path.split('/').last;
    return File('$assetDir/$name').readAsString(encoding: utf8);
  };

  await Api.instance.init();

  try {
    await S2T.instance.load();
  } catch (_) {
    // 轉換表讀不到就原樣輸出。通知會是簡體而不是繁體，
    // 但不該讓整個服務起不來。
  }
}

/// 目前的未讀數。
///
/// 用 [api.fetchBadges] 而**不是** fetchNotice——後者會把提醒標成已讀，
/// 等於一邊查一邊把使用者的紅點清掉。
Future<({int notice, int pm, Map<String, int> views})> badges() =>
    api.fetchBadges();
