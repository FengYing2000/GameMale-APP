import 'dart:js_interop';

/// 這個瀏覽器還在分頁裡看網頁，還沒把它加到主畫面。
///
/// 加到主畫面之後沒有網址列、全螢幕、有自己的圖示，體感就跟一般 App 一樣。
/// 實作在 `web/index.html` 的 `window.gmInstall`。
@JS('gmInstall.needed')
external JSBoolean _needed();

bool get needsInstall => _needed().toDart;

@JS('gmInstall.standalone')
external JSBoolean _standalone();

/// 以主畫面 App（沒有網址列）的方式開著
bool get isStandalone {
  try {
    return _standalone().toDart;
  } catch (_) {
    return false;
  }
}
