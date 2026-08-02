import 'dart:io';

import 'package:peckish/shared/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Full adoption of `openhearth_design` (upgraded from the v0.2-era
/// typography-only tier): Peckish's themes ARE the shared OhTheme
/// builders, whole — colors, ladder, buttons, inputs. These locks keep
/// any hand-rolled ThemeData or raw hex from creeping back in.
void main() {
  test('the app themes are the shared OhTheme builders, field for field',
      () {
    // ThemeData has no value equality; the text ladder and color scheme
    // together are the fingerprint that catches a hand-rolled divergence.
    expect(AppTheme.light.textTheme, OhTheme.light().textTheme);
    expect(AppTheme.light.colorScheme, OhTheme.light().colorScheme);
    expect(AppTheme.light.scaffoldBackgroundColor,
        OhTheme.light().scaffoldBackgroundColor);
    expect(AppTheme.dark.textTheme, OhTheme.hearthDark().textTheme);
    expect(AppTheme.dark.colorScheme, OhTheme.hearthDark().colorScheme);
  });

  test('no hand-rolled theme and no raw hex anywhere in the theme layer',
      () {
    final theme = File('lib/shared/theme/app_theme.dart').readAsStringSync();
    expect(theme, contains('OhTheme.light()'));
    expect(theme, contains('OhTheme.hearthDark()'));
    expect(theme.contains('ColorScheme.fromSeed'), isFalse,
        reason: 'the shared builders own the scheme');
    expect(theme.contains('TextTheme('), isFalse,
        reason: 'the ladder must come from openhearth_design');

    final colors =
        File('lib/shared/theme/app_colors.dart').readAsStringSync();
    expect(RegExp(r'Color\(0x').hasMatch(colors), isFalse,
        reason: 'app colors are semantic ALIASES onto OhColors — raw hex '
            'is how the boilerplate purple got in last time');
    expect(colors, contains('OhColors.'));
  });
}
