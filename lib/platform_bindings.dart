import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gm_api/http.dart';
import 'package:gm_api/s2t.dart';
import 'package:path_provider/path_provider.dart';

/// 把 Flutter 專屬的東西接到純 Dart 的 `gm_api` 上。
///
/// `gm_api` 刻意不依賴 Flutter，這樣 PWA 後端才能重用同一套論壇解析。
/// 代價是它拿不到 path_provider 與 rootBundle，所以那兩件事改成由平台端注入，
/// 就是這個檔案在做的事。**任何用到 Api 或 S2T 的進入點都要先呼叫
/// [installFlutterBindings]**——目前是 `main()` 與背景任務。
Future<void> installFlutterBindings() async {
  if (kIsWeb) {
    // 瀏覽器不准跨網域打論壇（論壇沒送 CORS 標頭），所以改打自己網站上的
    // 轉發路徑，由伺服器代打。同源請求瀏覽器會自動帶 cookie，
    // 登入狀態就交給它管，不需要 PersistCookieJar。
    kOrigin = '${Uri.base.origin}/gm';
    S2T.assetLoader = rootBundle.loadString;
    await Api.instance.init();
    return;
  }

  Api.cookieJarFactory = () {
    // 這裡不能 await（工廠是同步的），所以先用已經取好的目錄
    final dir = _supportDir;
    if (dir == null) return CookieJar();
    return PersistCookieJar(storage: FileStorage('$dir/cookies'));
  };

  S2T.assetLoader = rootBundle.loadString;

  try {
    _supportDir = (await getApplicationSupportDirectory()).path;
  } catch (_) {
    // 取不到目錄就用記憶體 cookie jar，登入狀態不會留著但不會整個掛掉。
    // 測試環境沒有 path_provider 外掛，走的就是這條。
    _supportDir = null;
  }
}

String? _supportDir;
