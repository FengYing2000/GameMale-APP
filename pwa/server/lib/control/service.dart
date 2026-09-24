import 'models.dart';
import 'store.dart';
import 'tokens.dart';

/// 測試碼 token 的狀態
enum BetaState {
  ok,

  /// 沒帶 token（還沒輸入過測試碼）
  missing,

  /// 簽章不對、格式不對
  invalid,

  /// 後台把這組碼停用或刪掉了
  disabled,
  expired,

  /// 這台裝置被從碼上解除綁定
  removed,
}

class BetaCheck {
  const BetaCheck(this.state, [this.code, this.device]);
  final BetaState state;
  final BetaCode? code;
  final Device? device;
  bool get ok => state == BetaState.ok;
}

class ActivateResult {
  const ActivateResult.fail(this.message)
      : ok = false,
        token = null,
        code = null;
  const ActivateResult.ok(this.token, this.code)
      : ok = true,
        message = '';
  final bool ok;
  final String message;
  final String? token;
  final BetaCode? code;
}

/// 擋下 `/gm` 轉發時要回什麼
class GateBlock {
  const GateBlock(this.status, this.body);
  final int status;
  final Map<String, Object?> body;
}

/// 測試碼、維護模式、版本檢查的規則。不碰 HTTP，方便單獨測。
class ControlService {
  ControlService(
    this.store,
    this.signer, {
    DateTime Function()? clock,
    this.webBuild,
  }) : _clock = clock ?? DateTime.now;

  final ControlStore store;
  final TokenSigner signer;
  final DateTime Function() _clock;

  /// 目前部署的網頁版 build 號（讀 build/web/version.json）
  final int Function()? webBuild;

  DateTime get now => _clock().toUtc();
  ControlSettings get settings => store.settings;

  static final _deviceId = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  BetaCheck checkBeta(String? token) {
    if (token == null || token.isEmpty) return const BetaCheck(BetaState.missing);
    final p = signer.verify(token);
    if (p == null || p['k'] != 'beta') return const BetaCheck(BetaState.invalid);
    final code = store.codeById('${p['c']}');
    if (code == null || !code.enabled) return BetaCheck(BetaState.disabled, code);
    if (code.expired(now)) return BetaCheck(BetaState.expired, code);
    final device = code.device('${p['d']}');
    if (device == null) return BetaCheck(BetaState.removed, code);
    return BetaCheck(BetaState.ok, code, device);
  }

  /// 輸入測試碼、綁定這台裝置。同一台重複啟用只會更新資料、不多佔名額
  ActivateResult activate({
    required String input,
    required String deviceId,
    String platform = '',
    String model = '',
    String version = '',
  }) {
    if (!_deviceId.hasMatch(deviceId)) return const ActivateResult.fail('裝置識別碼不正確');
    final code = store.codeByInput(input);
    if (code == null) return const ActivateResult.fail('測試碼不存在，請確認有沒有打錯');
    if (!code.enabled) return const ActivateResult.fail('這組測試碼已停用');
    if (code.expired(now)) return const ActivateResult.fail('這組測試碼已過期');

    var device = code.device(deviceId);
    if (device == null) {
      if (code.maxDevices > 0 && code.devices.length >= code.maxDevices) {
        return ActivateResult.fail('這組測試碼已經綁滿 ${code.maxDevices} 台裝置');
      }
      device = Device(id: deviceId, firstSeen: now, lastSeen: now);
      code.devices.add(device);
    }
    device
      ..platform = _clip(platform, 16)
      ..model = _clip(model, 80)
      ..appVersion = _clip(version, 32)
      ..lastSeen = now;
    store.save();
    return ActivateResult.ok(
      signer.sign({'k': 'beta', 'c': code.id, 'd': deviceId, 't': now.millisecondsSinceEpoch ~/ 1000}),
      code,
    );
  }

  /// App 裡的「解除此裝置綁定」：把名額還回去
  bool unbind(String? token) {
    final b = checkBeta(token);
    if (b.code == null || b.device == null) return false;
    b.code!.devices.remove(b.device);
    store.save();
    return true;
  }

  /// App 每次啟動、從背景回來時問的那一支
  Map<String, Object?> status({
    required String platform,
    int build = 0,
    String version = '',
    String? token,
  }) {
    final s = settings;
    final beta = checkBeta(token);
    if (beta.ok) {
      final d = beta.device!
        ..lastSeen = now
        ..platform = _clip(platform, 16);
      if (version.isNotEmpty) d.appVersion = _clip(version, 32);
      store.markDirty();
    }

    final bypass = beta.ok && beta.code!.bypass;
    final maintenanceOn = s.maintenance && !bypass;
    final betaOk = !s.betaRequired || beta.ok;
    final required = s.minBuild > 0 && build > 0 && build < s.minBuild;

    return {
      'canUse': !maintenanceOn && betaOk && !required,
      'maintenance': {
        'on': maintenanceOn,
        'message': s.maintenanceMessage,
        // 維護中、但這組碼可以略過——App 顯示一條提醒就好
        'bypassed': s.maintenance && bypass,
      },
      'beta': {
        'required': s.betaRequired,
        'valid': beta.ok,
        'reason': beta.state.name,
        if (beta.code != null && beta.ok) 'hint': beta.code!.hint,
        if (beta.code?.expiresAt != null && beta.ok)
          'expiresAt': beta.code!.expiresAt!.toIso8601String(),
      },
      'update': {
        'latest': _latestFor(platform, build),
        'required': required,
      },
    };
  }

  Map<String, Object?>? _latestFor(String platform, int build) {
    if (platform == 'web') {
      // 網頁版不用下載：部署了新版，重新整理就拿到了
      final deployed = webBuild?.call() ?? 0;
      if (deployed <= build) return null;
      final r = store.releaseByBuild(deployed);
      return {
        'version': r?.version ?? '',
        'build': deployed,
        'notes': r?.notes ?? '',
        'url': '',
      };
    }
    final r = store.latest(platform);
    if (r == null || r.build <= build) return null;
    return {
      'version': r.version,
      'build': r.build,
      'date': r.date.toIso8601String(),
      'notes': r.notes,
      'url': r.urlFor(platform),
      'size': platform == 'ios' ? r.iosSize : r.androidSize,
    };
  }

  /// 網頁版的 `/gm` 轉發要不要放行。原生 App 直連論壇，擋不到——
  /// 只有網頁版在伺服器端真正擋得住
  GateBlock? gate(String? token) {
    final s = settings;
    if (!s.maintenance && !s.betaRequired) return null;
    final beta = checkBeta(token);
    if (s.maintenance && !(beta.ok && beta.code!.bypass)) {
      return GateBlock(503, {'gate': 'maintenance', 'message': s.maintenanceMessage});
    }
    if (s.betaRequired && !beta.ok) {
      return const GateBlock(403, {'gate': 'beta'});
    }
    return null;
  }

  // ── 後台 ─────────────────────────────────────────────

  List<BetaCode> createCodes({
    int count = 1,
    String note = '',
    int maxDevices = 2,
    DateTime? expiresAt,
    bool bypass = false,
  }) {
    final out = <BetaCode>[];
    for (var i = 0; i < count.clamp(1, 100); i++) {
      String code;
      do {
        code = newBetaCode();
      } while (store.codeByInput(code) != null);
      final c = BetaCode(
        id: randomHex(6),
        code: code,
        note: _clip(note, 200),
        maxDevices: maxDevices.clamp(0, 1000),
        expiresAt: expiresAt?.toUtc(),
        bypass: bypass,
        createdAt: now,
      );
      store.codes.add(c);
      out.add(c);
    }
    store.save();
    return out;
  }

  AppRelease upsertRelease({
    required String version,
    required int build,
    DateTime? date,
    String notes = '',
    String iosUrl = '',
    String androidUrl = '',
    int iosSize = 0,
    int androidSize = 0,
  }) {
    var r = store.releaseByBuild(build);
    if (r == null) {
      r = AppRelease(version: version, build: build, date: date ?? now);
      store.releases.add(r);
    }
    r
      ..version = version
      ..date = (date ?? r.date).toUtc()
      ..notes = notes
      ..iosUrl = iosUrl
      ..androidUrl = androidUrl
      ..iosSize = iosSize
      ..androidSize = androidSize;
    store.releases.sort((a, b) => b.build.compareTo(a.build));
    store.save();
    return r;
  }

  static String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;
}
