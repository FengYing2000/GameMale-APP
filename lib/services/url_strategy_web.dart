/// 網頁版保留瀏覽器歷史。
///
/// 早期版本這裡呼叫 `setUrlStrategy(null)` 想關掉歷史、讓 iOS 的原生滑動
/// 沒東西可退，只留 Flutter 自己的手勢。但那條路的雙重動畫治不乾淨
/// （iOS 的滑動即使在歷史根部仍會有視覺）。改成相反的策略：**保留歷史**，
/// 讓 iOS 原生滑動正常運作，而把 Flutter 的頁面轉場整個拿掉
/// （見 theme.dart 的 _NoTransition），這樣只剩 iOS 一套動畫。
///
/// 所以這裡現在什麼都不做——保留預設的歷史整合。
void configureWebUrlStrategy() {}
