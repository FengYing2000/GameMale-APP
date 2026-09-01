import 'package:flutter_web_plugins/url_strategy.dart';

/// 讓網頁版**完全不碰瀏覽器歷史**。
///
/// 為什麼要這樣：iOS 16.4 起，加到主畫面的網頁 App 有自己的邊緣滑動返回，
/// 而 Flutter 的 Cupertino 轉場也有一個。兩個同時作用，滑一次就會看到
/// 返回動畫跑兩遍，還會有「好幾層頁面疊在一起」的錯覺。
///
/// 試過 `overscroll-behavior-x: none`——**iOS Safari 不理它**，那個手勢照跑。
/// 真正有效的是讓歷史裡根本沒有可以回去的項目：沒有上一頁，系統的手勢
/// 就不會有任何動作，返回完全交給 Flutter 自己處理，跟原生 App 一致。
///
/// 代價是網址列不會反映目前頁面（主畫面 App 本來就沒有網址列），
/// 而且重新整理會回到首頁。
void installNoHistoryUrlStrategy() => setUrlStrategy(null);
