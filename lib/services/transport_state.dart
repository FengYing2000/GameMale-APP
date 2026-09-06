import 'package:flutter/foundation.dart';

/// 論壇連線目前是不是走瀏覽器（Cloudflare 擋著時）。
///
/// **為什麼要做成可監聽的**：圖片元件在 build 當下讀這個值決定走哪條路。
/// App 剛啟動時它是 false（還沒撞到 403），首頁的圖片就全走了直連、失敗，
/// 而且**沒有任何東西會讓它們重建**——等文字請求把傳輸切成瀏覽器時，
/// 圖片早就掛掉了。實機症狀是「文字讀得到、圖片全部載入失敗」。
///
/// 有了這個 notifier，切換的瞬間所有圖片會一起重建、改走瀏覽器。
final usingBrowserTransport = ValueNotifier<bool>(false);
