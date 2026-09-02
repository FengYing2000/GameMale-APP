import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 品牌色沿用論壇的簽到按鈕綠
const brand = Color(0xFF70A128);
const brandLight = Color(0xFF8DB943);
const accent = Color(0xFFF15A23);

ThemeData _base(Brightness b, [Color seed = brand]) {
  final dark = b == Brightness.dark;
  // 深色底下原色會太暗，統一往白色拉一點；綠色沿用手調過的 brandLight
  final primary = dark
      ? (seed == brand ? brandLight : Color.lerp(seed, Colors.white, .28)!)
      : seed;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: b,
  ).copyWith(
    primary: primary,
    surface: dark ? const Color(0xFF191C22) : Colors.white,
    // fromSeed 的淺色 onSurface 會帶一層主色調，看起來偏灰；壓成近黑比較好讀
    onSurface: dark ? null : const Color(0xFF15171C),
  );

  final bg = dark ? const Color(0xFF0F1115) : const Color(0xFFF2F3F7);

  return ThemeData(
    useMaterial3: true,
    // 網頁版：頁面切換不做任何 Flutter 動畫。
    //
    // 為什麼：iOS 加到主畫面的 App 本身就有原生的邊緣滑動返回（會滑出
    // 上一頁的快照）。只要 Flutter 這邊也有轉場或滑動手勢，兩個就會疊在
    // 一起——使用者看到的「返回跳兩次／好幾頁疊著」就是這麼來的。
    // 把 Flutter 的轉場整個拿掉，返回動畫完全交給 iOS 原生那一套，
    // 就只剩一個、而且是最順的原生手感。前進（點進帖子）變成瞬間出現，
    // 少了滑入動畫，但換來乾淨不打架。原生 App 不受影響。
    pageTransitionsTheme: kIsWeb
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.iOS: _NoTransition(),
            TargetPlatform.android: _NoTransition(),
            TargetPlatform.macOS: _NoTransition(),
            TargetPlatform.windows: _NoTransition(),
            TargetPlatform.linux: _NoTransition(),
          })
        : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: '.SF Pro Text',
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xFF2A2F38) : const Color(0xFFE4E6EB),
      thickness: 0.5,
      space: 0.5,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface.withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      indicatorColor: brand.withValues(alpha: 0.16),
      height: 62,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

ThemeData lightThemeOf(Color seed) => _base(Brightness.light, seed);
ThemeData darkThemeOf(Color seed) => _base(Brightness.dark, seed);

final lightTheme = _base(Brightness.light);
final darkTheme = _base(Brightness.dark);

/// 次要文字色，列表的作者、時間、板塊簡介都用這個
/// 次要文字。淺色底下要壓得比深色底更實 —— 同樣的透明度，
/// 白底上的灰是「看不清楚」，深底上的灰卻剛好
Color subtle(BuildContext c) {
  final s = Theme.of(c).colorScheme;
  return s.onSurface
      .withValues(alpha: s.brightness == Brightness.dark ? 0.62 : 0.78);
}

/// 更次要的文字（時間、計數）。淺色模式原本 0.38 在白底上只有 2.8:1，
/// 小字幾乎讀不到，拉到 0.60 才過得去
Color faint(BuildContext c) {
  final s = Theme.of(c).colorScheme;
  return s.onSurface
      .withValues(alpha: s.brightness == Brightness.dark ? 0.46 : 0.60);
}


/// 網頁版專用：頁面瞬間切換，不做任何動畫也不帶滑動手勢。
/// 返回的視覺完全交給 iOS 主畫面 App 的原生邊緣滑動。
class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
