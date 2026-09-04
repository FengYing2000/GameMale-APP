/// 原生版有系統中文字體，不需要自己內建（也不該內建：那會讓 IPA／APK
/// 白白多好幾 MB，而且字體長相會跟系統其他 App 不一致）。
Future<void> loadCjkFont() async {}

/// 原生版用系統字體，回 null 讓 Flutter 自己決定
String? get cjkFontFamily => null;
