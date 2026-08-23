import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 主題強調色。深淺兩種模式都用同一顆種子色去產配色
enum Accent {
  blue('海藍', Color(0xFF2F6FB5)),
  forum('論壇綠', Color(0xFF70A128)),
  violet('紫羅蘭', Color(0xFF7A5AF8)),
  teal('青碧', Color(0xFF00897B)),
  rose('玫瑰', Color(0xFFD5427C)),
  amber('琥珀', Color(0xFFE08A00));

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

  ImagePolicy imagePolicy = ImagePolicy.always;
  AppLang lang = AppLang.auto;
  ThemeMode themeMode = ThemeMode.system;
  Accent accent = Accent.blue;

  /// 在主題列表標出自己回過的帖。要對每個主題各問一次論壇
  bool markReplied = true;

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
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, v.name);
  }

  Future<void> setAccent(Accent v) async {
    accent = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, v.name);
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

  Future<void> setThemeMode(ThemeMode v) async {
    themeMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, v.name);
  }
}
