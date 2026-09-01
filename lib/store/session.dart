import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';

class SessionStore extends ChangeNotifier {
  static const _key = 'gm.user';

  bool ready = false;
  bool loggedIn = false;
  int? uid;
  String name = '';
  String avatar = '';
  SignInfo? sign;
  String? error;

  /// 每次登入狀態改變就 +1。分頁被 IndexedStack 保活著不會自己重建，
  /// 各頁比對這個值就知道要不要重抓。
  int revision = 0;

  /// 未讀數。顯示成數字而不只是一顆點——「有東西」跟「有 5 封」差很多。
  int noticeCount = 0;
  int pmCount = 0;

  bool get hasNewNotice => noticeCount > 0;
  bool get hasNewPm => pmCount > 0;

  /// 私訊的未讀數是不是由對話列表算出來的。
  ///
  /// **這個旗標是為了修一個很煩的行為**：論壇只要開過私訊列表，就會把
  /// 頁首那個提醒數歸零，但對話本身還是未讀的。若照樣拿頁首的數字覆蓋，
  /// 紅點會亮個幾秒就消失，而使用者根本還沒讀那則訊息。
  /// 所以列表給過數字之後，頁首就不准再把它調低。
  bool _pmFromList = false;

  /// 頁首提醒選單抓到的未讀數
  void setBadges({required int notice, required int pm}) {
    var changed = false;
    if (notice != noticeCount) {
      noticeCount = notice;
      changed = true;
    }
    // 頁首的私訊數只在「變多」或「還沒問過對話列表」時採用
    if (!_pmFromList || pm > pmCount) {
      if (pm != pmCount) {
        pmCount = pm;
        changed = true;
      }
      if (pm > pmCount) _pmFromList = false;
    }
    if (changed) notifyListeners();
  }

  /// 開了提醒頁＝當作看過了（下次重抓會再依伺服器校正）
  void markNoticesSeen() {
    if (noticeCount != 0) {
      noticeCount = 0;
      notifyListeners();
    }
  }

  /// 對話列表算出來的未讀總數。這是私訊未讀的**真正依據**——
  /// 每則對話自己的未讀數只有真的進去看過才會歸零。
  void setPmUnreadCount(int count) {
    _pmFromList = true;
    if (count != pmCount) {
      pmCount = count;
      notifyListeners();
    }
  }

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
    revision++;
    notifyListeners();
  }

  void applyUser(SessionUser user) {
    final was = uid;
    _apply(user);
    if (was != uid) revision++;
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
    revision++;
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
