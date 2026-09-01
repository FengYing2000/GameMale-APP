import 'dart:convert';
import 'dart:io';

import 'webpush.dart';

/// 訂閱清單。第一階段先用 JSON 檔——資料量就是幾筆，
/// 為了它架資料庫沒有意義。等要接論壇多使用者再換 SQLite。
class SubscriptionStore {
  SubscriptionStore(this.file);

  final File file;
  final Map<String, PushSubscription> _byEndpoint = {};

  Future<void> load() async {
    if (!await file.exists()) return;
    final raw = json.decode(await file.readAsString()) as List;
    for (final e in raw) {
      final sub = PushSubscription.fromJson((e as Map).cast<String, dynamic>());
      _byEndpoint[sub.endpoint] = sub;
    }
  }

  Future<void> _flush() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
        json.encode(_byEndpoint.values.map((s) => s.toJson()).toList()));
  }

  int get length => _byEndpoint.length;
  List<PushSubscription> get all => _byEndpoint.values.toList();

  /// endpoint 當主鍵：同一台裝置重新訂閱會拿到同一個 endpoint，
  /// 直接覆蓋就好，不會愈存愈多筆。
  Future<void> add(PushSubscription sub) async {
    _byEndpoint[sub.endpoint] = sub;
    await _flush();
  }

  Future<bool> remove(String endpoint) async {
    if (_byEndpoint.remove(endpoint) == null) return false;
    await _flush();
    return true;
  }
}
