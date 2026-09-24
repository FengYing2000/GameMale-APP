/// App 控制台的資料：測試碼、綁定的裝置、版本、全站開關。
///
/// 這裡刻意**不碰論壇帳號**：測試碼綁的是 App 自己產生的隨機裝置 ID，
/// 不是論壇的 uid／帳號。伺服器依舊不保存任何論壇登入資料。
library;

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

/// 全站開關
class ControlSettings {
  ControlSettings({
    this.betaRequired = false,
    this.maintenance = false,
    this.maintenanceMessage = '',
    this.minBuild = 0,
  });

  /// 需要測試碼才能用。關掉＝正式開放，所有人都能用
  bool betaRequired;

  /// 維護模式：除了 [BetaCode.bypass] 的碼，全部擋在維護畫面
  bool maintenance;
  String maintenanceMessage;

  /// 低於這個 build 號的 App 強制更新；0＝不限
  int minBuild;

  factory ControlSettings.fromJson(Map<String, Object?> j) => ControlSettings(
        betaRequired: j['betaRequired'] == true,
        maintenance: j['maintenance'] == true,
        maintenanceMessage: (j['maintenanceMessage'] as String?) ?? '',
        minBuild: (j['minBuild'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
        'betaRequired': betaRequired,
        'maintenance': maintenance,
        'maintenanceMessage': maintenanceMessage,
        'minBuild': minBuild,
      };
}

/// 綁在某組測試碼上的一台裝置（或一個瀏覽器）
class Device {
  Device({
    required this.id,
    this.platform = '',
    this.model = '',
    this.appVersion = '',
    required this.firstSeen,
    required this.lastSeen,
  });

  final String id;
  String platform;
  String model;
  String appVersion;
  final DateTime firstSeen;
  DateTime lastSeen;

  factory Device.fromJson(Map<String, Object?> j) => Device(
        id: j['id'] as String,
        platform: (j['platform'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
        appVersion: (j['appVersion'] as String?) ?? '',
        firstSeen: _date(j['firstSeen']) ?? DateTime.now().toUtc(),
        lastSeen: _date(j['lastSeen']) ?? DateTime.now().toUtc(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'platform': platform,
        'model': model,
        'appVersion': appVersion,
        'firstSeen': _iso(firstSeen),
        'lastSeen': _iso(lastSeen),
      };
}

class BetaCode {
  BetaCode({
    required this.id,
    required this.code,
    this.note = '',
    this.maxDevices = 2,
    this.expiresAt,
    this.enabled = true,
    this.bypass = false,
    required this.createdAt,
    List<Device>? devices,
  }) : devices = devices ?? [];

  /// 內部編號（網址與 token 用），跟給人看的碼分開：
  /// 碼可以重發，編號不變
  final String id;
  final String code;

  /// 發給誰、用途
  String note;

  /// 0＝不限
  int maxDevices;
  DateTime? expiresAt;
  bool enabled;

  /// 維護模式期間照樣能用（自己測試用的碼）
  bool bypass;
  final DateTime createdAt;
  final List<Device> devices;

  bool expired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  Device? device(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// 給使用者看的遮罩版：GMAB-****-XY12
  String get hint {
    final parts = code.split('-');
    if (parts.length < 3) return '****';
    return [parts.first, for (var i = 1; i < parts.length - 1; i++) '****', parts.last]
        .join('-');
  }

  factory BetaCode.fromJson(Map<String, Object?> j) => BetaCode(
        id: j['id'] as String,
        code: j['code'] as String,
        note: (j['note'] as String?) ?? '',
        maxDevices: (j['maxDevices'] as num?)?.toInt() ?? 0,
        expiresAt: _date(j['expiresAt']),
        enabled: j['enabled'] != false,
        bypass: j['bypass'] == true,
        createdAt: _date(j['createdAt']) ?? DateTime.now().toUtc(),
        devices: [
          for (final d in (j['devices'] as List? ?? const []))
            Device.fromJson((d as Map).cast<String, Object?>()),
        ],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'code': code,
        'note': note,
        'maxDevices': maxDevices,
        'expiresAt': _iso(expiresAt),
        'enabled': enabled,
        'bypass': bypass,
        'createdAt': _iso(createdAt),
        'devices': [for (final d in devices) d.toJson()],
      };
}

/// 一個發佈出去的版本。安裝檔放在公開的「只放安裝檔」repo，這裡只記網址
class AppRelease {
  AppRelease({
    required this.version,
    required this.build,
    required this.date,
    this.notes = '',
    this.iosUrl = '',
    this.androidUrl = '',
    this.iosSize = 0,
    this.androidSize = 0,
  });

  String version;
  final int build;
  DateTime date;

  /// 更新內容，一行一條
  String notes;
  String iosUrl;
  String androidUrl;
  int iosSize;
  int androidSize;

  String urlFor(String platform) => switch (platform) {
        'ios' => iosUrl,
        'android' => androidUrl,
        _ => '',
      };

  factory AppRelease.fromJson(Map<String, Object?> j) => AppRelease(
        version: (j['version'] as String?) ?? '',
        build: (j['build'] as num).toInt(),
        date: _date(j['date']) ?? DateTime.now().toUtc(),
        notes: (j['notes'] as String?) ?? '',
        iosUrl: (j['iosUrl'] as String?) ?? '',
        androidUrl: (j['androidUrl'] as String?) ?? '',
        iosSize: (j['iosSize'] as num?)?.toInt() ?? 0,
        androidSize: (j['androidSize'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'build': build,
        'date': _iso(date),
        'notes': notes,
        'iosUrl': iosUrl,
        'androidUrl': androidUrl,
        'iosSize': iosSize,
        'androidSize': androidSize,
      };
}
