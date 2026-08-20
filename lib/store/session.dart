import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/discuz.dart' as api;
import '../api/models.dart';

class SessionStore extends ChangeNotifier {
  static const _key = 'gm.user';

  bool ready = false;
  bool loggedIn = false;
  int? uid;
  String name = '';
  String avatar = '';
  SignInfo? sign;
  String? error;

  /// 冷啟動：先讀本機快取讓畫面有東西，再問伺服器 cookie 還有沒有效。
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final u = SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        uid = u.uid;
        name = u.name;
        avatar = u.avatar;
        loggedIn = u.loggedIn;
      }
    } catch (_) {
      // 首次啟動沒有存檔，忽略
    }

    // 任何一頁發現變回訪客就立刻反映到 UI，不要等下次冷啟動
    api.onSessionLost = markLoggedOut;

    try {
      final user = await api.checkSession();
      if (user != null) {
        _apply(user);
      } else {
        loggedIn = false;
      }
    } on DiscuzException catch (e) {
      // 連不上論壇時無從判斷，保留快取狀態並把錯誤帶給畫面
      error = e.message;
    }

    ready = true;
    notifyListeners();
  }

  /// session 過期：清掉本機狀態但不打登出 API（cookie 早就沒用了）
  void markLoggedOut() {
    if (!loggedIn) return;
    loggedIn = false;
    sign = null;
    notifyListeners();
  }

  void applyUser(SessionUser user) {
    _apply(user);
    notifyListeners();
  }

  void _apply(SessionUser user) {
    loggedIn = true;
    uid = user.uid;
    if (user.name.isNotEmpty) name = user.name;
    avatar = user.avatar;
    _persist();
  }

  void setSign(SignInfo? s) {
    sign = s;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } on DiscuzException {
      // 伺服器端沒清成功也要讓本地登出
    }
    loggedIn = false;
    uid = null;
    name = '';
    avatar = '';
    sign = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(SessionUser(uid: uid, name: name, avatar: avatar, loggedIn: loggedIn).toJson()),
    );
  }
}
