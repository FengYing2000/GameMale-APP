import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';

import '../services/browser_fetch_stub.dart'
    if (dart.library.io) '../services/browser_fetch.dart';
import 'session.dart';

/// 一個已保存的帳號。
///
/// **密碼不放這裡**——它存在系統安全區（Keychain/Keystore），只有勾了
/// 「記住密碼」才有，而且永遠不進 SharedPreferences。
class Account {
  Account({
    required this.uid,
    required this.name,
    required this.avatar,
    this.username = '',
    this.cookies = '',
    this.remember = false,
  });

  final int uid;
  String name;
  String avatar;

  /// 登入用的帳號名（記住帳號，登入頁自動帶入）
  String username;

  /// cookie 快照，"name=value; name=value"。切回這個帳號時灌回連線層。
  String cookies;

  /// 有沒有把密碼存進安全區
  bool remember;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'avatar': avatar,
        'username': username,
        'cookies': cookies,
        'remember': remember,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        uid: j['uid'] as int,
        name: (j['name'] ?? '') as String,
        avatar: (j['avatar'] ?? '') as String,
        username: (j['username'] ?? '') as String,
        cookies: (j['cookies'] ?? '') as String,
        remember: (j['remember'] ?? false) as bool,
      );
}

/// 多帳號：全部存在**手機本機**（清單＋cookie 走 SharedPreferences，
/// 密碼走系統安全區）。**不上 VPS、網頁版不記**——網頁版的 cookie 由瀏覽器
/// 自己管，也沒有 Keychain，所以這個 store 在網頁版整個停用。
///
/// 切換帳號＝把目標帳號的 cookie 換進連線層＋同步 WebView，全程維持登入態，
/// 不會變回訪客、也就不會撞到論壇的人機驗證。
class AccountsStore extends ChangeNotifier {
  AccountsStore(this._session);

  final SessionStore _session;

  static const _key = 'gm.accounts';
  static const _curKey = 'gm.accounts.current';
  static const _pwPrefix = 'gm.pw.';

  // 網頁版不記密碼，連 secure storage 都不建
  final FlutterSecureStorage? _secure =
      kIsWeb ? null : const FlutterSecureStorage();

  final List<Account> _accounts = [];
  int? currentUid;
  bool ready = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  bool get hasMultiple => _accounts.length > 1;
  Account? get current => _byUid(currentUid);

  Account? _byUid(int? uid) {
    for (final a in _accounts) {
      if (a.uid == uid) return a;
    }
    return null;
  }

  /// 冷啟動載入清單
  Future<void> load() async {
    if (kIsWeb) {
      ready = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _accounts
          ..clear()
          ..addAll(list.map((e) => Account.fromJson(e as Map<String, dynamic>)));
      }
      currentUid = prefs.getInt(_curKey);
    } catch (_) {
      // 壞了就當沒有，不擋啟動
    }
    ready = true;
  }

  /// 把「目前這條連線登入的帳號」對齊到清單。
  ///
  /// 升級到多帳號版之前，使用者已經有一份登入 cookie 在連線層。冷啟動時
  /// [SessionStore.restore] 會判定它登入，這裡就把它收進清單當第一個帳號，
  /// 使用者不必重登。之後每次冷啟動也順手更新目前帳號的快照與頭像暱稱。
  Future<void> syncFromSession() async {
    if (kIsWeb) return;
    final uid = _session.uid;
    if (!_session.loggedIn || uid == null) return;

    final existing = _byUid(uid);
    if (existing == null) {
      await addOrUpdate(SessionUser(
        uid: uid,
        name: _session.name,
        avatar: _session.avatar,
        loggedIn: true,
      ));
    } else {
      existing.name = _session.name.isNotEmpty ? _session.name : existing.name;
      existing.avatar = _session.avatar;
      currentUid = uid;
      await _snapshotCurrent();
      await _persist();
      notifyListeners();
    }
  }

  /// 登入成功後把這個帳號存起來（或更新）。當下的連線 cookie 就是它的。
  Future<void> addOrUpdate(
    SessionUser user, {
    String username = '',
    String? password,
    bool remember = false,
  }) async {
    if (kIsWeb) return;
    final uid = user.uid;
    if (uid == null) return;

    var acc = _byUid(uid);
    if (acc == null) {
      acc = Account(uid: uid, name: user.name, avatar: user.avatar);
      _accounts.add(acc);
    } else {
      if (user.name.isNotEmpty) acc.name = user.name;
      acc.avatar = user.avatar;
    }
    if (username.isNotEmpty) acc.username = username;
    acc.cookies = await _currentCookieHeader();
    acc.remember = remember && password != null && password.isNotEmpty;

    // 密碼只進安全區，永遠不進 SharedPreferences
    if (acc.remember) {
      await _secure?.write(key: '$_pwPrefix$uid', value: password);
    } else if (password == null) {
      // 沒帶密碼＝這次不動密碼設定；帶了空密碼或 remember=false 才清
    }
    if (!acc.remember) {
      await _secure?.delete(key: '$_pwPrefix$uid');
    }

    currentUid = uid;
    await _persist();
    notifyListeners();
  }

  /// 切換到另一個已保存的帳號。
  Future<void> switchTo(int uid) async {
    if (kIsWeb || uid == currentUid) return;
    final target = _byUid(uid);
    if (target == null) return;

    // 1. 先把當前連線的 cookie 存回目前帳號（它可能在使用中更新過）
    await _snapshotCurrent();

    // 2. 連線層換成目標帳號的 cookie
    await Api.instance.clearCookies();
    if (target.cookies.isNotEmpty) {
      await Api.instance.seedCookies(target.cookies);
    }

    // 3. WebView 那份 cookie 也要換，否則被驗證擋著時走 WebView 會抓回
    //    上一個帳號的頁面（跟登出那個 bug 同一個道理）
    await BrowserFetch.instance.clearCookies();
    Api.resetTransport();

    // 4. 指標移過去
    currentUid = uid;
    await _persist();

    // 5. 樂觀把畫面切成目標帳號 → revision 跳動 → 首頁自動用新 cookie 重抓校正
    _session.applyUser(SessionUser(
      uid: target.uid,
      name: target.name,
      avatar: target.avatar,
      loggedIn: true,
    ));
    notifyListeners();
  }

  /// 刪除一個已保存的帳號（連同它的密碼與 cookie）。
  Future<void> remove(int uid) async {
    if (kIsWeb) return;
    _accounts.removeWhere((a) => a.uid == uid);
    await _secure?.delete(key: '$_pwPrefix$uid');

    if (currentUid == uid) {
      // 刪掉的是目前帳號：有別的就切過去，沒有就登出
      if (_accounts.isNotEmpty) {
        await _persist();
        await switchTo(_accounts.first.uid);
        return;
      } else {
        currentUid = null;
        await Api.instance.clearCookies();
        await BrowserFetch.instance.clearCookies();
        Api.resetTransport();
        _session.markLoggedOut();
      }
    }
    await _persist();
    notifyListeners();
  }

  // 新增帳號時暫存「原本要回去的帳號」——登入沒成功就把它的 cookie 換回來。
  int? _addReturnUid;

  /// 開始新增帳號：先存好目前帳號的 cookie，再清空連線變「訪客」。
  ///
  /// **一定要清**：不清的話登入頁還是已登入狀態，論壇不給登入表單也不出
  /// 驗證碼，而且送出後 checkSession 會看到舊 session、隨便輸入都「成功」，
  /// 實際上根本沒登入新帳號。清成訪客才能真正登入另一個帳號。
  Future<void> beginAdd() async {
    if (kIsWeb) return;
    await _snapshotCurrent();
    _addReturnUid = currentUid;
    await Api.instance.clearCookies();
    await BrowserFetch.instance.clearCookies();
    Api.resetTransport();
  }

  /// 取消新增（登入頁沒成功就離開）：把原本帳號的 cookie 換回來。
  Future<void> cancelAdd() async {
    if (kIsWeb) return;
    final uid = _addReturnUid;
    _addReturnUid = null;
    if (uid == null) return;
    final acc = _byUid(uid);
    await Api.instance.clearCookies();
    if (acc != null && acc.cookies.isNotEmpty) {
      await Api.instance.seedCookies(acc.cookies);
    }
    await BrowserFetch.instance.clearCookies();
    Api.resetTransport();
  }

  /// 新增成功，不必還原
  void finishAdd() => _addReturnUid = null;

  /// 讀某帳號存的密碼（沒有記住就回 null）
  Future<String?> passwordFor(int uid) async {
    if (kIsWeb) return null;
    final acc = _byUid(uid);
    if (acc == null || !acc.remember) return null;
    return _secure?.read(key: '$_pwPrefix$uid');
  }

  Future<String> _currentCookieHeader() async {
    final cookies = await Api.instance.allCookies();
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<void> _snapshotCurrent() async {
    final cur = _byUid(currentUid);
    if (cur == null) return;
    final header = await _currentCookieHeader();
    if (header.isNotEmpty) cur.cookies = header;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_accounts.map((a) => a.toJson()).toList()),
    );
    if (currentUid != null) {
      await prefs.setInt(_curKey, currentUid!);
    } else {
      await prefs.remove(_curKey);
    }
  }
}
