import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/discuz.dart' as api;
import '../api/models.dart';

/// 收藏過哪些帖子。
///
/// 論壇的帖子頁不會告訴你「你收藏過這帖沒有」——收藏連結永遠寫著「收藏本帖」，
/// 只有真的按下去才會回「您已收藏过本主题」。所以星星要一開始就是實心的，
/// 只能自己把收藏清單抓回來記著。
///
/// 清單存在本機，換帳號會整份丟掉；每天最多自動重抓一次。
class FavoriteStore extends ChangeNotifier {
  static const _key = 'gm.favThreads';
  static const _stampKey = 'gm.favThreadsAt';
  static const _uidKey = 'gm.favThreadsUid';

  /// 收藏很多的人清單會很長，設個上限免得無止境翻頁
  static const _maxPages = 30;

  /// tid → favid。取消收藏要 favid，只記 tid 的話就只能加不能減
  Map<int, int> _favids = <int, int>{};
  int? _uid;
  bool _loading = false;

  bool contains(int tid) => _favids.containsKey(tid);
  int? favidOf(int tid) => _favids[tid];
  bool get loading => _loading;
  int get count => _favids.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getInt(_uidKey);
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      _favids = <int, int>{};
      if (data is Map) {
        for (final e in data.entries) {
          final t = int.tryParse('${e.key}');
          if (t == null) continue;
          _favids[t] = e.value is int ? e.value as int : 0;
        }
      } else if (data is List) {
        // 舊版只存 tid 陣列，沒有 favid。先讓星星亮起來，
        // 下次重抓時再補上 favid（沒有它就取消不了收藏）
        for (final t in data.whereType<int>()) {
          _favids[t] = 0;
        }
      }
      notifyListeners();
    } catch (_) {
      // 壞掉就當作沒有，重抓一次就好
    }
  }

  /// 登入狀態改變時呼叫
  Future<void> setUser(int? uid) async {
    if (_uid == uid) return;
    _uid = uid;
    _favids = <int, int>{};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove(_key);
      await prefs.remove(_stampKey);
      await prefs.remove(_uidKey);
    } else {
      await prefs.setInt(_uidKey, uid);
      await prefs.remove(_stampKey);
    }
  }

  /// 一天自動重抓一次；`force` 用在使用者手動下拉重整
  Future<void> refresh({bool force = false}) async {
    final uid = _uid;
    if (uid == null || _loading) return;

    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_stampKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    // 沒有 favid 的舊資料也要重抓，不然取消收藏會找不到編號
    final stale = _favids.isEmpty || _favids.values.every((v) => v == 0);
    if (!force && !stale && age < const Duration(days: 1).inMilliseconds) {
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final found = <int, int>{};
      for (var page = 1; page <= _maxPages; page++) {
        final r = await api.fetchFavorites(uid, page: page);
        if (r.list.isEmpty) break;
        for (final t in r.list) {
          found[t.tid] = t.favid ?? 0;
        }
        if (page >= r.pager.total) break;
      }
      if (found.isNotEmpty) {
        _favids = found;
        await _save();
        await prefs.setInt(_stampKey, DateTime.now().millisecondsSinceEpoch);
      }
    } on DiscuzException {
      // 抓不到就沿用舊的，總比整排變空心好
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> add(int tid, {int favid = 0}) async {
    if (_favids[tid] == favid && _favids.containsKey(tid)) return;
    _favids[tid] = favid;
    notifyListeners();
    await _save();
  }

  Future<void> remove(int tid) async {
    if (_favids.remove(tid) == null) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode({for (final e in _favids.entries) '${e.key}': e.value}));
  }
}
