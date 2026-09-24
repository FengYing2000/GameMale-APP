import 'dart:js_interop';

/// 網頁版的更新＝重新整理：入口檔是 no-cache，重載就拿到新部署的版本
void reloadPage() => _location.reload();

@JS('location')
external _Location get _location;

extension type _Location(JSObject _) implements JSObject {
  external void reload();
}
