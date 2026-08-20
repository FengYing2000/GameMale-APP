import 'package:flutter/material.dart';

/// 品牌色沿用論壇的簽到按鈕綠
const brand = Color(0xFF70A128);
const brandLight = Color(0xFF8DB943);
const accent = Color(0xFFF15A23);

ThemeData _base(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: b,
  ).copyWith(
    primary: dark ? brandLight : brand,
    surface: dark ? const Color(0xFF191C22) : Colors.white,
  );

  final bg = dark ? const Color(0xFF0F1115) : const Color(0xFFF2F3F7);

  return ThemeData(
    useMaterial3: true,
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

final lightTheme = _base(Brightness.light);
final darkTheme = _base(Brightness.dark);

/// 次要文字色，列表的作者、時間、板塊簡介都用這個
Color subtle(BuildContext c) =>
    Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.55);

Color faint(BuildContext c) =>
    Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.38);
