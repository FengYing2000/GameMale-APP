import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import '../services/browser_fetch_stub.dart'
    if (dart.library.io) '../services/browser_fetch.dart';
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
        // 論壇明確回訪客頁 = 登入已在論壇端失效。連同本機快取一起清掉，
        // 不要只設 loggedIn=false 卻留著舊 uid/name/avatar——那會有兩個症狀：
        //  1. 畫面顯示「未登入」卻還掛著舊頭像舊暱稱（殘影）
        //  2. 重新登入若是同一帳號，applyUser 的 was!=uid 會是 false，
        //     revision 不遞增，被保活的首頁不會自動重抓，得手動下拉
        // 只在「明確拿到訪客頁」時清；連不上／被 CF 擋走的是下面的 exception
        // 分支，那是暫時性的，要保留快取不能清。
        await _clearLocal();
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
    if (!loggedIn && uid == null) return;
    // 跟 restore() 同一個道理：連 uid/name/avatar 一起清，否則會有殘影，
    // 且重登同一帳號時 revision 不遞增、被保活的首頁不會自動重抓。
    revision++;
    _resetFields();
    notifyListeners();
    unawaited(_clearPersisted());
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
    // WebView 那份 cookie 也要清。只清 App 這份的話，被驗證擋著時走的是
    // WebView，而它還是登入狀態——抓回來的會是舊帳號的頁面，驗證碼也會
    // 對不上（那是另一個 session 的碼）。
    if (!kIsWeb) await BrowserFetch.instance.clearCookies();
    // 讓下一個請求重新判斷擋不擋，並允許驗證頁立刻跳出來
    Api.resetTransport();
    revision++;
    await _clearLocal();
    notifyListeners();
  }

  /// 清掉登入相關的記憶體欄位（同步）。
  void _resetFields() {
    loggedIn = false;
    uid = null;
    name = '';
    avatar = '';
    sign = null;
  }

  /// 清掉持久化的登入快取。
  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 記憶體 + 持久化一起清。
  Future<void> _clearLocal() async {
    _resetFields();
    await _clearPersisted();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(SessionUser(uid: uid, name: name, avatar: avatar, loggedIn: loggedIn).toJson()),
    );
  }
}
