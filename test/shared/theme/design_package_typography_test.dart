import 'dart:io';

import 'package:peckish/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Tier-T adoption of `openhearth_design`: Peckish's Material TextTheme ladder
/// must come from [OhTypography.materialTextTheme] (the package copy is
/// byte-identical to the block the habit-lineage apps hand-rolled). Peckish
/// has no goldens yet, so these WHOLE-STYLE equality assertions are the lock:
/// per the ohStyle strict-equality pattern, `TextStyle.==` compares every
/// field (letterSpacing, height, wordSpacing, decoration, inherit, …), so ANY
/// local override of ANY property — not just family/size/weight — fails here.
void main() {
  const roles = <String, TextStyle? Function(TextTheme)>{
    'displayLarge': _displayLarge,
    'displayMedium': _displayMedium,
    'displaySmall': _displaySmall,
    'headlineLarge': _headlineLarge,
    'headlineMedium': _headlineMedium,
    'headlineSmall': _headlineSmall,
    'titleLarge': _titleLarge,
    'titleMedium': _titleMedium,
    'titleSmall': _titleSmall,
    'bodyLarge': _bodyLarge,
    'bodyMedium': _bodyMedium,
    'bodySmall': _bodySmall,
    'labelLarge': _labelLarge,
    'labelMedium': _labelMedium,
    'labelSmall': _labelSmall,
  };

  for (final theme in {'light': AppTheme.light, 'dark': AppTheme.dark}.entries) {
    test(
        '${theme.key} theme text ladder matches OhTypography.materialTextTheme '
        '(WHOLE TextStyle — letterSpacing/height included — all 15 roles)', () {
      // ThemeData merges the provided TextTheme over its typography defaults
      // (and those defaults carry colors/letterSpacing/height), so the app
      // style can't equal the bare package style. Rebuild the same baseline
      // WITHOUT a textTheme, merge the package role over it, and require the
      // app role to whole-equal that: any app-local override of ANY TextStyle
      // field — letterSpacing, height, decoration, … — breaks the equality.
      final baseline = ThemeData(
        useMaterial3: true,
        colorScheme: theme.value.colorScheme,
      );
      for (final role in roles.entries) {
        final app = role.value(theme.value.textTheme)!;
        final base = role.value(baseline.textTheme)!;
        final pkg = role.value(OhTypography.materialTextTheme)!;
        expect(app, base.merge(pkg), reason: role.key);
      }
    });
  }

  test('app_theme.dart sources its TextTheme from the design package '
      '(no hand-rolled ladder left behind)', () {
    final source =
        File('lib/shared/theme/app_theme.dart').readAsStringSync();
    expect(source, contains('OhTypography.materialTextTheme'),
        reason: 'the ladder must come from openhearth_design');
    expect(source.contains('TextTheme('), isFalse,
        reason: 'the hand-rolled const TextTheme block must be gone — '
            'a drifting local copy is exactly what the package prevents');
  });
}

TextStyle? _displayLarge(TextTheme t) => t.displayLarge;
TextStyle? _displayMedium(TextTheme t) => t.displayMedium;
TextStyle? _displaySmall(TextTheme t) => t.displaySmall;
TextStyle? _headlineLarge(TextTheme t) => t.headlineLarge;
TextStyle? _headlineMedium(TextTheme t) => t.headlineMedium;
TextStyle? _headlineSmall(TextTheme t) => t.headlineSmall;
TextStyle? _titleLarge(TextTheme t) => t.titleLarge;
TextStyle? _titleMedium(TextTheme t) => t.titleMedium;
TextStyle? _titleSmall(TextTheme t) => t.titleSmall;
TextStyle? _bodyLarge(TextTheme t) => t.bodyLarge;
TextStyle? _bodyMedium(TextTheme t) => t.bodyMedium;
TextStyle? _bodySmall(TextTheme t) => t.bodySmall;
TextStyle? _labelLarge(TextTheme t) => t.labelLarge;
TextStyle? _labelMedium(TextTheme t) => t.labelMedium;
TextStyle? _labelSmall(TextTheme t) => t.labelSmall;
