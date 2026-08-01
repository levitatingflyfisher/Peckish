import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Peckish wears the shared OpenHearth themes, whole: hearth terracotta
/// on linen by day, the hearth-dark ember family by night. Typography,
/// radii, buttons, inputs — all the shared builders' word. Anything
/// Peckish-specific is a semantic alias in app_colors.dart, which itself
/// only points at OhColors: no raw hex anywhere in this app.
///
/// Fonts are BUNDLED (assets/fonts/, declared in pubspec) and referenced
/// by family — never fetched at runtime. No font egress on first launch.
class AppTheme {
  AppTheme._();

  /// Floating, with a right margin wide enough to clear a 56dp FAB plus its
  /// own 16dp padding. The v0.9.1 phone verdict was "the edit popup bar
  /// covers the plus": the log-confirmation toast presents in the nav
  /// shell's root Scaffold (`app_router.dart`'s `_TabShell`), which has no
  /// FAB of its own — so Today's FAB never raises for it, and the default
  /// fixed, full-width SnackBar sits right under the + button. `floating`
  /// with this margin keeps the toast clear of the FAB band regardless of
  /// which Scaffold in the nesting actually shows it.
  static const _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    insetPadding: EdgeInsets.only(left: 16, right: 88, bottom: 16),
  );

  static final ThemeData light =
      OhTheme.light().copyWith(snackBarTheme: _snackBarTheme);
  static final ThemeData dark =
      OhTheme.hearthDark().copyWith(snackBarTheme: _snackBarTheme);
}
