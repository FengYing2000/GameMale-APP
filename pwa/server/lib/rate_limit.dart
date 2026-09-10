import 'package:shelf/shelf.dart';

/// 逐來源 IP 的滑動視窗限流。
///
/// **為什麼要**：`/gm` 是公開的論壇轉發，而且現在帶論壇的 UserAgent 白名單
/// （免人機驗證）。沒有限流的話，任何人掃到 `852111.xyz/gm` 就能把它當成
/// 「免驗證、隱藏自己 IP」的跳板對論壇灌大量請求——論壇只會看到本站 VPS 的
/// IP，可能反過來封本站、撤白名單。限流把單一來源的頻率壓在正常瀏覽遠遠
/// 用不到的上限之下，擋的是濫用、不是使用者。
///
/// 上限刻意設得很寬（預設每分鐘 120 次 `/gm`）：一個人正常逛論壇、甚至開著
/// 「回帖檢測」批次比對，每分鐘也遠低於這個數；只有腳本式的大量請求才會撞到。
class RateLimiter {
  RateLimiter({
    this.maxPerWindow = 120,
    this.window = const Duration(minutes: 1),
  });

  final int maxPerWindow;
  final Duration window;

  final _hits = <String, List<DateTime>>{};
  DateTime _lastSweep = DateTime.now();

  /// 這個來源現在還能不能放行。放行就記一筆。
  bool allow(String key) {
    final now = DateTime.now();
    _maybeSweep(now);

    final cutoff = now.subtract(window);
    final list = _hits.putIfAbsent(key, () => <DateTime>[]);
    list.removeWhere((t) => t.isBefore(cutoff));
    if (list.length >= maxPerWindow) return false;
    list.add(now);
    return true;
  }

  /// 定期把整個視窗內都沒有請求的來源清掉，`_hits` 才不會無限長大。
  void _maybeSweep(DateTime now) {
    if (now.difference(_lastSweep) < window) return;
    _lastSweep = now;
    final cutoff = now.subtract(window);
    _hits.removeWhere((_, list) {
      list.removeWhere((t) => t.isBefore(cutoff));
      return list.isEmpty;
    });
  }
}

/// 從 Caddy 加的 `X-Forwarded-For` 取真實來源 IP。
///
/// 這台沒有 Cloudflare（只有 Caddy 反代），所以真實 IP 是 XFF 的第一個。
/// 直接用 shelf 拿到的是 Caddy 容器的內網 IP，會把所有人算成同一個來源，
/// 那就變成全站共用一條限流——絕對不能那樣。取不到就回 `unknown`
/// （極少見；那批請求會共用一個 bucket，寧可保守）。
String clientIp(Request r) {
  final xff = r.headers['x-forwarded-for'];
  if (xff != null && xff.trim().isNotEmpty) {
    return xff.split(',').first.trim();
  }
  final real = r.headers['x-real-ip'];
  if (real != null && real.trim().isNotEmpty) return real.trim();
  return 'unknown';
}
