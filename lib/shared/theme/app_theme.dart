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

  static final ThemeData light = OhTheme.light();
  static final ThemeData dark = OhTheme.hearthDark();
}
