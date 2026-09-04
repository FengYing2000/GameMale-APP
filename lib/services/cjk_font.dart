import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// 網頁版要自己內建中文字體。
///
/// **為什麼非做不可**：CanvasKit 不用系統字體，它只畫得出自己載進去的
/// 字體。遇到沒有的字時，Flutter 會即時去 `fonts.gstatic.com` 抓 Noto
/// 後備字體——在抓回來之前，畫面上就是一整片方格打叉。
///
/// 所以改成自己出。字體檔放在 `web/`（不是 pubspec 的 assets），
/// 這樣**只有網頁版會帶上它**，原生的 IPA／APK 完全不受影響。
///
/// 檔名帶內容雜湊，可以給不可變的長快取；換字體時改檔名即可。
const _fontAsset = 'fonts/gm-cjk-6683468f.ttf';

/// 字族名稱。刻意不叫 Noto——這是裁切過的自用版本，
/// 名字撞上系統字體的話除錯會很痛苦。
const _family = 'GMSans';

String? get cjkFontFamily => _family;

/// 把字體載進來。**要在 runApp 之前 await**，否則第一幀仍會是方格。
///
/// index.html 有 `<link rel="preload">` 讓下載跟 main.dart.js／canvaskit.wasm
/// 平行進行，所以這裡通常不會真的多等——檔案早就在快取裡了。
Future<void> loadCjkFont() async {
  try {
    final loader = FontLoader(_family)..addFont(_load());
    await loader.load();
  } catch (_) {
    // 載不到就退回 Flutter 原本的 gstatic 後備：會閃一下方格，
    // 但至少字還是看得到，不能因為字體就讓整個 App 開不起來。
  }
}

Future<ByteData> _load() async {
  // 用 rootBundle 讀不到——這個檔在 web/ 而不是 pubspec 的 assets 裡，
  // 所以直接對自己的伺服器要（同源，走瀏覽器快取；index.html 已經
  // preload 過，這裡通常是直接命中）。
  //
  // 用 Dio 的裸實例：Api 那條已經被指到論壇的轉發路徑上，不能共用。
  final res = await Dio().getUri<List<int>>(
    Uri.base.resolve(_fontAsset),
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = res.data;
  if (bytes == null || bytes.isEmpty) {
    throw StateError('字體是空的');
  }
  return ByteData.sublistView(Uint8List.fromList(bytes));
}
