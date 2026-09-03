import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'webpush.dart';

import 'secret_box.dart';

/// 一個帳號最多留幾筆推播訂閱
const int _maxSubscriptions = 3;

/// 一個論壇帳號，以及它綁的裝置。
class Account {
  Account({
    required this.id,
    required this.username,
    required this.cookieSealed,
    this.cookieStatus = 'ok',
    this.authFailStreak = 0,
    this.autoSign = false,
    this.signReminderAt = '09:00',
    this.notifyNotice = true,
    this.notifyPm = true,
    this.lastNotice = 0,
    this.lastPm = 0,
    this.lastSignDate,
    this.lastRemindDate,
    this.lastCheckedAt,
    List<PushSubscription>? subscriptions,
  }) : subscriptions = subscriptions ?? [];

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        username: j['username'] as String,
        cookieSealed: j['cookieSealed'] as String,
        cookieStatus: j['cookieStatus'] as String? ?? 'ok',
        authFailStreak: j['authFailStreak'] as int? ?? 0,
        autoSign: j['autoSign'] as bool? ?? false,
        signReminderAt: j['signReminderAt'] as String? ?? '09:00',
        notifyNotice: j['notifyNotice'] as bool? ?? true,
        notifyPm: j['notifyPm'] as bool? ?? true,
        lastNotice: j['lastNotice'] as int? ?? 0,
        lastPm: j['lastPm'] as int? ?? 0,
        lastSignDate: j['lastSignDate'] as String?,
        lastRemindDate: j['lastRemindDate'] as String?,
        lastCheckedAt: j['lastCheckedAt'] as String?,
        subscriptions: ((j['subscriptions'] as List?) ?? const [])
            .map((e) => PushSubscription.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
      );

  final String id;
  final String username;

  /// 加密後的論壇 cookie。**明文不落地。**
  String cookieSealed;

  /// `ok` 或 `expired`。過期會推一則請使用者重新登入，
  /// 並且停止繼續拿失效的 cookie 去敲論壇。
  String cookieStatus;

  /// 連續幾輪明確看到訪客頁。
  ///
  /// 要連著兩輪才算真的過期。單獨一次可能是論壇那邊的暫時狀況，
  /// 而「請重新登入」是會在半夜把人吵醒的通知，寧可晚五分鐘也不要誤推。
  int authFailStreak;

  bool autoSign;

  /// 沒開自動簽到時，每天這個時間推一則提醒（24 小時制 HH:mm）
  String signReminderAt;

  bool notifyNotice;
  bool notifyPm;

  /// 上次看到的未讀數。只有「變多」才通知——讀掉變少不吵、
  /// 沒變也不會重複吵。
  int lastNotice;
  int lastPm;

  /// 上次簽到成功的日期（yyyy-MM-dd，台北時間）
  String? lastSignDate;

  /// 上次推「記得簽到」的日期。跟 [lastSignDate] 分開存——
  /// 混在同一個欄位會讓「提醒過」被誤判成「簽到過」。
  String? lastRemindDate;

  String? lastCheckedAt;

  final List<PushSubscription> subscriptions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'cookieSealed': cookieSealed,
        'cookieStatus': cookieStatus,
        'authFailStreak': authFailStreak,
        'autoSign': autoSign,
        'signReminderAt': signReminderAt,
        'notifyNotice': notifyNotice,
        'notifyPm': notifyPm,
        'lastNotice': lastNotice,
        'lastPm': lastPm,
        'lastSignDate': lastSignDate,
        'lastRemindDate': lastRemindDate,
        'lastCheckedAt': lastCheckedAt,
        'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
      };
}

/// 帳號與訂閱的存放。
///
/// 用 JSON 檔而不是資料庫：這是自用服務，帳號數量是個位數，
/// 為它架一套 schema 沒有意義。寫入走「先寫暫存檔再 rename」，
/// 中途斷電不會留下寫到一半的檔案。
class AccountStore {
  AccountStore(this.file, this.box);

  final File file;
  final SecretBox box;
  final Map<String, Account> _byId = {};

  /// 登入後給前端的 session token → 帳號 id。
  /// 這是 PWA 自己的 session，跟論壇的 cookie 是兩回事。
  final Map<String, String> _tokens = {};

  Future<void> load() async {
    if (!await file.exists()) return;
    final raw = json.decode(await file.readAsString()) as Map<String, dynamic>;
    for (final e in (raw['accounts'] as List? ?? const [])) {
      final a = Account.fromJson((e as Map).cast<String, dynamic>());
      _byId[a.id] = a;
    }
    _tokens.addAll(
        ((raw['tokens'] as Map?) ?? const {}).cast<String, String>());
  }

  Future<void> flush() async {
    await file.parent.create(recursive: true);
    // 先寫暫存檔再 rename：rename 在同一個檔案系統上是原子操作，
    // 寫到一半斷電也不會把原本的資料弄成半截
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode({
      'accounts': _byId.values.map((a) => a.toJson()).toList(),
      'tokens': _tokens,
    }));
    await tmp.rename(file.path);
  }

  List<Account> get all => _byId.values.toList();
  int get length => _byId.length;

  Account? byId(String id) => _byId[id];

  Account? byUsername(String username) {
    for (final a in _byId.values) {
      if (a.username.toLowerCase() == username.toLowerCase()) return a;
    }
    return null;
  }

  Account? byToken(String? token) =>
      token == null ? null : _byId[_tokens[token]];

  /// 建立或更新一個帳號（同一個論壇帳號重登就是換掉 cookie）
  Future<Account> upsert({
    required String username,
    required String cookiePlain,
  }) async {
    final existing = byUsername(username);
    if (existing != null) {
      existing.cookieSealed = box.seal(cookiePlain);
      existing.cookieStatus = 'ok';
      existing.authFailStreak = 0;
      await flush();
      return existing;
    }
    final a = Account(
      id: _randomId(),
      username: username,
      cookieSealed: box.seal(cookiePlain),
    );
    _byId[a.id] = a;
    await flush();
    return a;
  }

  Future<String> issueToken(Account a) async {
    final t = _randomId(24);
    _tokens[t] = a.id;
    await flush();
    return t;
  }

  Future<void> revokeToken(String token) async {
    _tokens.remove(token);
    await flush();
  }

  /// 綁一台裝置到這個帳號。
  ///
  /// endpoint 當主鍵：同一台裝置重新訂閱拿到的是同一個 endpoint，
  /// 直接換掉就好，不會愈存愈多筆。同時把它從別的帳號移除——
  /// 一台裝置同時屬於兩個帳號的話會收到兩份通知。
  Future<void> addSubscription(Account a, PushSubscription sub) async {
    for (final other in _byId.values) {
      other.subscriptions.removeWhere((s) => s.endpoint == sub.endpoint);
    }
    a.subscriptions.add(sub);
    // 每次重新「加到主畫面」都會拿到一個新的 endpoint，而舊的在 Apple 那邊
    // 還會存活一段時間——不設上限的話一個人就累積出十幾筆，每則通知都要
    // 送十幾次。手機上看起來只有一則（同 tag 會合併），但那是白花的請求。
    // 保留最近幾筆就夠：真正在用的一定是最後訂閱的那台。
    if (a.subscriptions.length > _maxSubscriptions) {
      a.subscriptions.removeRange(
          0, a.subscriptions.length - _maxSubscriptions);
    }
    await flush();
  }

  Future<bool> removeSubscription(String endpoint) async {
    var hit = false;
    for (final a in _byId.values) {
      final before = a.subscriptions.length;
      a.subscriptions.removeWhere((s) => s.endpoint == endpoint);
      if (a.subscriptions.length != before) hit = true;
    }
    if (hit) await flush();
    return hit;
  }

  Future<void> remove(Account a) async {
    _byId.remove(a.id);
    _tokens.removeWhere((_, id) => id == a.id);
    await flush();
  }

  /// 解出論壇 cookie。金鑰換過或檔案被動過就會丟 [FormatException]。
  String openCookie(Account a) => box.open(a.cookieSealed);
}

String _randomId([int bytes = 12]) {
  final r = math.Random.secure();
  return List<int>.generate(bytes, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
