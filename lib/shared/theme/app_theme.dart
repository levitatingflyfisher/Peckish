import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // Fonts are BUNDLED (assets/fonts/, declared in pubspec) and referenced by
  // family — not fetched from fonts.gstatic.com at runtime. This keeps the app
  // fully local-first: no font egress on first launch. See app_text_styles.dart.
  //
  // The Material text ladder is the shared openhearth_design copy — byte-equal
  // to the const block this file used to hand-roll, so adopting it is zero
  // visual change by construction (locked by the whole-TextStyle equivalence
  // test — Peckish has no goldens yet). Peckish's paprika/flour
  // surfaces below stay app-local: they are identity, not shared tokens.
  static const TextTheme _textTheme = OhTypography.materialTextTheme;

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.paprika,
      brightness: Brightness.light,
      surface: AppColors.flour,
      onSurface: AppColors.ink,
    ),
    scaffoldBackgroundColor: AppColors.flour,
    shadowColor: AppColors.ink.withValues(alpha: 0.15),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paprika,
      foregroundColor: AppColors.flour,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: AppColors.flour2,
      shadowColor: AppColors.ink.withValues(alpha: 0.1),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.paprika,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    ),
    scaffoldBackgroundColor: AppColors.darkSurface,
    shadowColor: Colors.black.withValues(alpha: 0.3),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface2,
      foregroundColor: AppColors.flour,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: AppColors.darkSurface2,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
