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

  Set<int> _tids = <int>{};
  int? _uid;
  bool _loading = false;

  bool contains(int tid) => _tids.contains(tid);
  bool get loading => _loading;
  int get count => _tids.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getInt(_uidKey);
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _tids = list.whereType<int>().toSet();
        notifyListeners();
      }
    } catch (_) {
      // 壞掉就當作沒有，重抓一次就好
    }
  }

  /// 登入狀態改變時呼叫
  Future<void> setUser(int? uid) async {
    if (_uid == uid) return;
    _uid = uid;
    _tids = <int>{};
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
    if (!force && _tids.isNotEmpty && age < const Duration(days: 1).inMilliseconds) {
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final found = <int>{};
      for (var page = 1; page <= _maxPages; page++) {
        final r = await api.fetchFavorites(uid, page: page);
        if (r.list.isEmpty) break;
        found.addAll(r.list.map((t) => t.tid));
        if (page >= r.pager.total) break;
      }
      if (found.isNotEmpty) {
        _tids = found;
        await prefs.setString(_key, jsonEncode(found.toList()));
        await prefs.setInt(
            _stampKey, DateTime.now().millisecondsSinceEpoch);
      }
    } on DiscuzException {
      // 抓不到就沿用舊的，總比整排變空心好
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> add(int tid) async {
    if (!_tids.add(tid)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_tids.toList()));
  }

  Future<void> remove(int tid) async {
    if (!_tids.remove(tid)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_tids.toList()));
  }
}
