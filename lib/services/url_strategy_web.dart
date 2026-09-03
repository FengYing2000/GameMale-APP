import 'package:flutter_web_plugins/url_strategy.dart';

/// 網頁版**關掉**與瀏覽器歷史的整合。
///
/// iOS 主畫面 App 自己有一套邊緣滑動返回，它是靠 history.back() 運作的。
/// 只要瀏覽器歷史裡有東西，那套就會動——而 Flutter 自己也有 Cupertino 的
/// 拖曳返回，兩個疊在一起就是「返回跳兩次」「先閃一下上一頁」。
///
/// 試過的另一條路（保留歷史、改讓 Flutter 不做轉場）沒有比較好：Flutter
/// 會瞬間換頁，iOS 的快照動畫卻還在跑，反而變成「已經回到首頁了又閃一下
/// 剛剛那頁」。
///
/// 所以改成讓 **Flutter 完全掌管導覽**：歷史裡永遠只有一筆，iOS 的手勢
/// 沒有東西可退、完全不作動，返回只剩 Flutter 自己那一套（拖曳手勢與
/// 左上角的返回鍵都照常）。
///
/// 代價：網址列不反映目前頁面（主畫面 App 本來就沒有網址列），
/// 重新整理會回到首頁。
void configureWebUrlStrategy() => setUrlStrategy(null);
