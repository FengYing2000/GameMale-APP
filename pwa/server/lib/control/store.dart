import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// 控制台資料的存放處：一個 JSON 檔（docker volume 裡的 `/data/control.json`）。
///
/// 量很小（幾十組碼、上百台裝置），用資料庫是殺雞用牛刀；JSON 也方便
/// 出事時直接打開來看、手改。
///
/// 寫入一律「寫暫存檔再改名」：寫到一半當機也不會留下半個檔案把資料弄壞。
/// 裝置的「最後上線」每次開 App 都會變，那種只標記、最多每分鐘落地一次。
class ControlStore {
  ControlStore([this.file]);

  /// null＝只放記憶體（測試用）
  final File? file;

  ControlSettings settings = ControlSettings();
  final codes = <BetaCode>[];
  final releases = <AppRelease>[];

  Future<void> _writing = Future.value();
  Timer? _debounce;

  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    final j = json.decode(await f.readAsString()) as Map<String, Object?>;
    settings = ControlSettings.fromJson(
        (j['settings'] as Map?)?.cast<String, Object?>() ?? const {});
    codes
      ..clear()
      ..addAll([
        for (final c in (j['codes'] as List? ?? const []))
          BetaCode.fromJson((c as Map).cast<String, Object?>()),
      ]);
    releases
      ..clear()
      ..addAll([
        for (final r in (j['releases'] as List? ?? const []))
          AppRelease.fromJson((r as Map).cast<String, Object?>()),
      ]);
  }

  Map<String, Object?> toJson() => {
        'settings': settings.toJson(),
        'codes': [for (final c in codes) c.toJson()],
        'releases': [for (final r in releases) r.toJson()],
      };

  /// 馬上存（後台的每個操作）
  Future<void> save() {
    _debounce?.cancel();
    _debounce = null;
    final f = file;
    if (f == null) return Future.value();
    final text = const JsonEncoder.withIndent('  ').convert(toJson());
    // 排隊寫，兩個請求同時存也不會互相蓋掉一半
    _writing = _writing.then((_) async {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    });
    return _writing;
  }

  /// 不急的變動（裝置最後上線時間）：一分鐘內合併成一次寫入
  void markDirty() {
    if (file == null || _debounce != null) return;
    _debounce = Timer(const Duration(minutes: 1), save);
  }

  BetaCode? codeById(String id) {
    for (final c in codes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 使用者輸入的碼：不分大小寫、容忍空白與少打的連字號
  BetaCode? codeByInput(String input) {
    final want = normalizeCode(input);
    if (want.isEmpty) return null;
    for (final c in codes) {
      if (normalizeCode(c.code) == want) return c;
    }
    return null;
  }

  /// 最新的一版（有該平台安裝檔的）；[platform] 為空＝不管平台
  AppRelease? latest([String platform = '']) {
    AppRelease? best;
    for (final r in releases) {
      if (platform.isNotEmpty && r.urlFor(platform).isEmpty) continue;
      if (best == null || r.build > best.build) best = r;
    }
    return best;
  }

  AppRelease? releaseByBuild(int build) {
    for (final r in releases) {
      if (r.build == build) return r;
    }
    return null;
  }
}

String normalizeCode(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
