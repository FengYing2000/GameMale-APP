import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_label.dart';

/// App 能不能用：測試碼、維護模式、強制更新。
///
/// 規則全在 852111.xyz 的控制台（pwa/server/lib/control），這裡只負責問、
/// 記住答案、決定蓋上哪個畫面。
///
/// * **原生版**直連論壇，伺服器擋不到，只能靠這裡在啟動時擋。上次確認
///   能用的話先開門、背景再問（不拖慢啟動）；連不上伺服器時沿用上次的
///   結果 7 天，VPS 掛掉不會把大家鎖在門外。
/// * **網頁版**真正的把關在伺服器端（論壇轉發直接回 403／503），這裡只是
///   把原因講清楚。
enum GateStage {
  /// 第一次開、還沒有任何答案
  checking,
  open,
  needCode,
  maintenance,
  updateRequired,

  /// 需要確認卻連不上伺服器，而且沒有可沿用的結果
  unreachable,
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    this.notes = '',
    this.url = '',
    this.size = 0,
  });

  final String version;
  final int build;
  final String notes;

  /// 安裝檔網址；網頁版是空的（重新整理就是更新）
  final String url;
  final int size;

  static UpdateInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final build = (j['build'] as num?)?.toInt() ?? 0;
    if (build <= 0) return null;
    return UpdateInfo(
      version: '${j['version'] ?? ''}',
      build: build,
      notes: '${j['notes'] ?? ''}',
      url: '${j['url'] ?? ''}',
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class GateStore extends ChangeNotifier {
  GateStore({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              // 400／429 的 JSON 要自己讀出訊息
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;

  /// 控制台在哪。網頁版就是自己；原生版固定打網頁版那台
  static String get origin => kIsWeb ? Uri.base.origin : 'https://852111.xyz';

  static const _grace = Duration(days: 7);
  static const _kDevice = 'gm.device';
  static const _kToken = 'gm.beta.token';
  static const _kLast = 'gm.gate.last';
  static const _kLastOk = 'gm.gate.lastOk';

  // iOS 的 Keychain 在刪 App 重裝後還在：重裝不會多佔一個裝置名額
  final FlutterSecureStorage? _secure = kIsWeb ? null : const FlutterSecureStorage();
  SharedPreferences? _prefs;

  GateStage stage = GateStage.checking;
  String maintenanceMessage = '';

  /// 維護中，但自己的碼可以略過
  bool maintenanceBypassed = false;
  bool betaRequired = false;

  /// 目前綁定的測試碼（遮罩）：GMAB-****-XY12
  String codeHint = '';
  DateTime? codeExpiresAt;
  UpdateInfo? update;
  bool updateRequired = false;
  String sourceUrl = '';
  String? error;

  String version = '';
  int build = 0;
  String deviceId = '';
  String? _token;

  // 回報給後台的裝置資料與論壇帳號（只有綁了測試碼的裝置會被記下來）
  DeviceLabel _label = const DeviceLabel();
  int? _forumUid;
  String _forumName = '';

  DateTime? _lastCheck;
  Future<void>? _inflight;
  Completer<void>? _opened;

  String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android';

  bool get isOpen => stage == GateStage.open;

  /// 有測試碼綁在這台上（可以解除）
  bool get hasCode => codeHint.isNotEmpty;

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {}
    _prefs = await SharedPreferences.getInstance();
    deviceId = await _read(_kDevice) ?? '';
    if (deviceId.length < 8) {
      deviceId = _newDeviceId();
      await _write(_kDevice, deviceId);
    }
    _token = await _read(_kToken);
    _label = await DeviceLabel.read();

    // 上次確認能用、而且還在寬限期內：先開門，背景再問
    final last = _cached();
    if (last != null && last['canUse'] == true && _withinGrace()) {
      _apply(last);
      unawaited(check(force: true));
    } else {
      await check(force: true);
    }
  }

  /// 等到可以用為止（開機流程裡，登入等論壇請求要排在這之後）
  Future<void> waitUntilOpen() {
    if (isOpen) return Future.value();
    return (_opened ??= Completer<void>()).future;
  }

  /// 問一次伺服器。沒 [force] 的話 10 分鐘內只問一次（從背景切回來時用）
  Future<void> check({bool force = false}) {
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return Future.value();
    }
    return _inflight ??= _check().whenComplete(() => _inflight = null);
  }

  /// 目前登入的論壇帳號。換帳號、登入、登出時呼叫；綁了測試碼的話
  /// 馬上回報一次，後台才看得到「這台現在是誰在用」
  void setForumUser(int? uid, String name) {
    if (uid == _forumUid && name == _forumName) return;
    _forumUid = uid;
    _forumName = name;
    if (hasCode) unawaited(check(force: true));
  }

  /// 放標頭而不是網址：伺服器的請求紀錄只記網址，暱稱不會出現在 log 裡。
  /// 標頭只能是 ASCII，中文要先編碼
  Map<String, String> _headers() => {
        'x-gm-token': ?_token,
        if (_label.model.isNotEmpty) 'x-gm-model': Uri.encodeComponent(_label.model),
        if (_label.os.isNotEmpty) 'x-gm-os': Uri.encodeComponent(_label.os),
        if (_forumUid != null) 'x-gm-forum-uid': '$_forumUid',
        if (_forumUid != null) 'x-gm-forum-name': Uri.encodeComponent(_forumName),
      };

  /// 網頁版的論壇轉發被擋時呼叫（一次載入會撞到好幾次，合併成一個）
  void onBlocked() {
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 3)) return;
    unawaited(check(force: true));
  }

  Future<void> _check() async {
    _lastCheck = DateTime.now();
    try {
      final res = await _dio.get<Object>(
        '$origin/api/app/status',
        queryParameters: {'platform': platform, 'build': '$build', 'version': version},
        options: Options(headers: _headers()),
      );
      final j = res.data;
      if (res.statusCode != 200 || j is! Map) throw StateError('HTTP ${res.statusCode}');
      final m = j.cast<String, Object?>();
      error = null;
      _apply(m);
      await _prefs?.setString(_kLast, json.encode(m));
      if (m['canUse'] == true) {
        await _prefs?.setInt(_kLastOk, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      error = '$e';
      // 連不上：上次確認能用、還在寬限期內就照舊。已經開著的也不因為一次
      // 失敗就蓋上（從背景切回來時網路常常還沒恢復）
      final last = _cached();
      if (!kIsWeb && last != null && last['canUse'] == true && _withinGrace()) {
        if (stage == GateStage.checking) _apply(last);
      } else if (stage != GateStage.open) {
        stage = GateStage.unreachable;
      }
    }
    _settle();
    notifyListeners();
  }

  void _apply(Map<String, Object?> j) {
    final m = (j['maintenance'] as Map?) ?? const {};
    final b = (j['beta'] as Map?) ?? const {};
    final u = (j['update'] as Map?) ?? const {};

    maintenanceMessage = '${m['message'] ?? ''}';
    maintenanceBypassed = m['bypassed'] == true;
    betaRequired = b['required'] == true;
    codeHint = b['valid'] == true ? '${b['hint'] ?? ''}' : '';
    codeExpiresAt = DateTime.tryParse('${b['expiresAt'] ?? ''}')?.toLocal();
    update = UpdateInfo.fromJson(u['latest']);
    updateRequired = u['required'] == true;
    sourceUrl = '${j['sourceUrl'] ?? ''}';

    stage = m['on'] == true
        ? GateStage.maintenance
        : updateRequired
            ? GateStage.updateRequired
            : betaRequired && b['valid'] != true
                ? GateStage.needCode
                : GateStage.open;
  }

  void _settle() {
    if (isOpen && _opened != null && !_opened!.isCompleted) _opened!.complete();
  }

  /// 輸入測試碼。成功回 null，失敗回給使用者看的原因
  Future<String?> activate(String code) async {
    try {
      final res = await _dio.post<Object>(
        '$origin/api/app/activate',
        data: {
          'code': code.trim(),
          'device': deviceId,
          'platform': platform,
          'model': _label.model,
          'os': _label.os,
          'version': version,
          if (_forumUid != null) 'forumUid': _forumUid,
          if (_forumUid != null) 'forumName': _forumName,
        },
      );
      final j = res.data;
      if (j is! Map) return '伺服器回應不正確（${res.statusCode}）';
      if (j['ok'] != true) return '${j['message'] ?? '啟用失敗'}';
      // 網頁版的 token 在 HttpOnly cookie 裡，不會出現在回應
      final token = j['token'];
      if (token is String && token.isNotEmpty) {
        _token = token;
        await _write(_kToken, token);
      }
      await check(force: true);
      return null;
    } on DioException catch (e) {
      return '連不上伺服器：${e.message ?? e.type.name}';
    }
  }

  /// 把名額還回去，這台之後要重新輸入測試碼
  Future<void> unbind() async {
    try {
      await _dio.post<Object>('$origin/api/app/unbind',
          options: Options(headers: {if (_token != null) 'x-gm-token': _token}));
    } on DioException {
      // 伺服器那邊沒解到也無妨，本機照樣清掉
    }
    _token = null;
    await _delete(_kToken);
    await check(force: true);
  }

  /// 更新日誌：[{version, build, date, notes}]
  Future<List<Map<String, Object?>>> changelog() async {
    final res = await _dio.get<Object>('$origin/api/app/changelog');
    final j = res.data;
    if (j is! Map) throw StateError('HTTP ${res.statusCode}');
    return [
      for (final r in (j['releases'] as List? ?? const [])) (r as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?>? _cached() {
    final s = _prefs?.getString(_kLast);
    if (s == null) return null;
    try {
      return (json.decode(s) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  bool _withinGrace() {
    final ok = _prefs?.getInt(_kLastOk);
    if (ok == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ok)) < _grace;
  }

  static String _newDeviceId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // 原生版放 Keychain／Keystore，失敗再退回一般偏好設定；網頁版只有後者
  Future<String?> _read(String key) async {
    try {
      final v = await _secure?.read(key: key);
      if (v != null) return v;
    } catch (_) {}
    return _prefs?.getString(key);
  }

  Future<void> _write(String key, String value) async {
    try {
      if (_secure != null) {
        await _secure.write(key: key, value: value);
        return;
      }
    } catch (_) {}
    await _prefs?.setString(key, value);
  }

  Future<void> _delete(String key) async {
    try {
      await _secure?.delete(key: key);
    } catch (_) {}
    await _prefs?.remove(key);
  }
}
