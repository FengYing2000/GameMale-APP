import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/widgets/quick_menu.dart' show forumTools;

/// 帖子裡的圖片什麼時候自動載入
enum ImagePolicy {
  always('一律載入', '不管用什麼網路都直接顯示'),
  wifiOnly('只在 Wi-Fi', '用行動網路時改成手動點開'),
  never('一律手動', '永遠只顯示佔位，點了才載');

  const ImagePolicy(this.label, this.desc);
  final String label;
  final String desc;
}

/// 介面語言
enum AppLang {
  auto('自動', '跟隨系統語言'),
  hant('繁體中文', '介面與論壇內容都顯示繁體'),
  hans('简体中文', '介面转为简体，论坛内容维持原样');

  const AppLang(this.label, this.desc);
  final String label;
  final String desc;
}

/// 主題強調色。取自 LGBTQ+ 六色彩虹旗，照旗子由上而下排：紅橙黃綠藍紫。
/// 深淺兩種模式都用同一顆種子色去產配色；預設仍是藍。
enum Accent {
  red('紅', Color(0xFFE40303)),
  orange('橙', Color(0xFFF08C00)),
  yellow('黃', Color(0xFFE0A800)),
  green('綠', Color(0xFF008026)),
  blue('藍', Color(0xFF2F6FB5)),
  violet('紫', Color(0xFF750787));

  const Accent(this.label, this.seed);
  final String label;
  final Color seed;
}

class SettingsStore extends ChangeNotifier {
  static const _kImage = 'gm.imagePolicy';
  static const _kLang = 'gm.lang';
  static const _kTheme = 'gm.theme';
  static const _kAccent = 'gm.accent';
  static const _kReplied = 'gm.replied';
  static const _kTwWords = 'gm.twWords';
  static const _kTools = 'gm.tools';
  static const _kAutoSign = 'gm.autoSign';

  ImagePolicy imagePolicy = ImagePolicy.always;
  AppLang lang = AppLang.auto;
  ThemeMode themeMode = ThemeMode.system;
  Accent accent = Accent.blue;

  /// 語言改變時 tick 一下，讓 GoRouter 重建整個頁面堆疊，
  /// 既有頁面才會用新語言重新 render（否則要下拉刷新才會變）
  final ValueNotifier<int> langTick = ValueNotifier<int>(0);

  /// 在主題列表標出自己回過的帖。要對每個主題各問一次論壇
  bool markReplied = true;

  /// 登入狀態下每天開 App 自動簽到。預設開（含覆蓋安裝時使用者沒手動關過的情況）
  bool autoSign = true;

  /// 背景檢查有沒有新提醒／新私訊，有就發本地通知

  /// 側邊欄「論壇功能」的顯示順序；沒設定過就用內建順序。
  /// 值是工具的 id，不在清單裡的代表被關掉了
  List<String>? _toolOrder;

  /// 把論壇內容的用詞也換成台灣說法（软件→軟體）。
  /// 會改掉帖子原本的字，跟網頁版對不起來，所以預設關閉
  bool taiwanWords = false;

  bool _onWifi = true;
  bool get onWifi => _onWifi;

  /// 現在這個當下該不該自動載圖
  bool get autoLoadImages => switch (imagePolicy) {
        ImagePolicy.always => true,
        ImagePolicy.wifiOnly => _onWifi,
        ImagePolicy.never => false,
      };

  /// 是否要把簡體內容轉成繁體
  bool get toTraditional => switch (lang) {
        AppLang.hant => true,
        AppLang.hans => false,
        AppLang.auto => _systemPrefersTraditional(),
      };

  static bool _systemPrefersTraditional() {
    final l = PlatformDispatcher.instance.locale;
    if (l.languageCode != 'zh') return true;   // 非中文環境預設繁體
    // zh-Hant / zh-TW / zh-HK / zh-MO 都算繁體
    final script = l.scriptCode?.toLowerCase();
    if (script == 'hant') return true;
    if (script == 'hans') return false;
    return const {'TW', 'HK', 'MO'}.contains(l.countryCode?.toUpperCase());
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    imagePolicy = ImagePolicy.values.firstWhere(
      (e) => e.name == prefs.getString(_kImage),
      orElse: () => ImagePolicy.always,
    );
    lang = AppLang.values.firstWhere(
      (e) => e.name == prefs.getString(_kLang),
      orElse: () => AppLang.auto,
    );
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == prefs.getString(_kTheme),
      orElse: () => ThemeMode.system,
    );
    accent = Accent.values.firstWhere(
      (e) => e.name == prefs.getString(_kAccent),
      orElse: () => Accent.blue,
    );
    markReplied = prefs.getBool(_kReplied) ?? true;
    taiwanWords = prefs.getBool(_kTwWords) ?? false;
    // 未設定過就預設開 —— 覆蓋安裝時沒手動關過的人也會是開的。
    // 之後新增的增強功能開關，一律沿用「?? true」讓覆蓋安裝預設開。
    autoSign = prefs.getBool(_kAutoSign) ?? true;
    _toolOrder = prefs.getStringList(_kTools);

    await _refreshNetwork();
    Connectivity().onConnectivityChanged.listen((_) => _refreshNetwork());

    notifyListeners();
  }

  Future<void> _refreshNetwork() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final wifi = result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet);
      if (wifi != _onWifi) {
        _onWifi = wifi;
        notifyListeners();
      }
    } catch (_) {
      // 取不到就當作 Wi-Fi，寧可載圖也不要莫名其妙都不顯示
      _onWifi = true;
    }
  }

  Future<void> setImagePolicy(ImagePolicy v) async {
    imagePolicy = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kImage, v.name);
  }

  Future<void> setLang(AppLang v) async {
    lang = v;
    // 先讓 _applyLang 之類的 listener 把解析層／UiLang 切好，
    // 再 tick 讓 GoRouter 用新語言重建頁面
    notifyListeners();
    langTick.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, v.name);
  }

  Future<void> setAccent(Accent v) async {
    accent = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, v.name);
  }

  /// 依使用者排好的順序給出要顯示的工具
  List<({String id, String label, IconData icon, String path})> get visibleTools {
    final order = _toolOrder;
    if (order == null) return forumTools;
    return [
      for (final id in order)
        for (final t in forumTools)
          if (t.id == id) t,
    ];
  }

  /// 有哪些被關掉了
  List<({String id, String label, IconData icon, String path})> get hiddenTools {
    final order = _toolOrder;
    if (order == null) return const [];
    return [for (final t in forumTools) if (!order.contains(t.id)) t];
  }

  Future<void> setToolOrder(List<String> ids) async {
    _toolOrder = ids;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTools, ids);
  }

  Future<void> resetTools() async {
    _toolOrder = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTools);
  }

  Future<void> setTaiwanWords(bool v) async {
    taiwanWords = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTwWords, v);
  }

  Future<void> setMarkReplied(bool v) async {
    markReplied = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReplied, v);
  }

  Future<void> setAutoSign(bool v) async {
    autoSign = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSign, v);
  }

  Future<void> setThemeMode(ThemeMode v) async {
    themeMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, v.name);
  }
}
