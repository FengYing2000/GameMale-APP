import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一筆回帖紀錄
class ReplyRecord {
  const ReplyRecord({
    required this.tid,
    required this.title,
    required this.excerpt,
    required this.at,
  });

  final int tid;
  final String title;
  final String excerpt;
  final DateTime at;

  Map<String, Object?> toJson() => {
        't': tid,
        'n': title,
        'e': excerpt,
        'a': at.millisecondsSinceEpoch,
      };

  static ReplyRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tid = raw['t'];
    final at = raw['a'];
    if (tid is! int || at is! int) return null;
    return ReplyRecord(
      tid: tid,
      title: raw['n'] as String? ?? '',
      excerpt: raw['e'] as String? ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// 回帖紀錄。論壇的「我的回覆」只查得到還在的帖子，而且要連線才看得到；
/// 這份留在本機，離線也能翻，帖子被刪了也還記得回過什麼。
class ReplyHistory extends ChangeNotifier {
  static const _key = 'gm.replyHistory';
  static const _max = 300;

  List<ReplyRecord> _items = const [];
  List<ReplyRecord> get items => _items;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _items = list
          .map(ReplyRecord.fromJson)
          .whereType<ReplyRecord>()
          .toList(growable: false);
      notifyListeners();
    } catch (_) {
      // 格式壞了就當作沒有，不值得為了它擋住 App 啟動
    }
  }

  Future<void> add(ReplyRecord r) async {
    // 同一帖回很多次只留最新那筆，不然列表會被洗版
    final next = [r, ..._items.where((e) => e.tid != r.tid)];
    _items = next.take(_max).toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> remove(int tid) async {
    _items = _items.where((e) => e.tid != tid).toList(growable: false);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items = const [];
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }
}
