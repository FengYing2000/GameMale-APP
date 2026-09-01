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
    // 網頁版要拿掉 Flutter 自己的拖曳返回手勢。
    //
    // 預設在 iOS 上用的是 CupertinoPageTransitionsBuilder，它自帶邊緣拖曳返回；
    // 而 iOS 16.4 起，加到主畫面的網頁 App **本身也有**滑動返回。兩個都在動，
    // 滑一次就會看到返回動畫跑兩遍。
    //
    // 這裡換成只有視覺、沒有手勢的版本：手勢交給 Safari，Flutter 只負責畫
    // 那一次轉場。外觀跟原本的 Cupertino 滑入一致。
    pageTransitionsTheme: kIsWeb
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.iOS: _SlideNoGestureTransitions(),
            TargetPlatform.android: _SlideNoGestureTransitions(),
            TargetPlatform.macOS: _SlideNoGestureTransitions(),
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


/// iOS 那種由右滑入、舊頁往左退的轉場，但**不含**拖曳返回手勢。
///
/// 只在網頁版用。原生版維持 Flutter 預設的 Cupertino 轉場（手勢要留著）。
class _SlideNoGestureTransitions extends PageTransitionsBuilder {
  const _SlideNoGestureTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.fastEaseInToSlowEaseOut;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: curve)),
      child: SlideTransition(
        // 舊頁往左退一小段，就是 iOS 的視差感
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.25, 0))
            .animate(CurvedAnimation(parent: secondaryAnimation, curve: curve)),
        child: child,
      ),
    );
  }
}
