import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// ohStyle's ambient ThemeData.iconTheme(color: primary) sits above
// IconButton's own filledTonal default (Flutter 3.38.7 merges
// IconButtonTheme over the ambient IconTheme), so a plain
// `IconButton.filledTonal` paints its glyph in `primary` — low contrast
// against the `secondaryContainer` fill it sits on. `OhIconButton.filledTonal`
// pins the correct `onSecondaryContainer` foreground at the widget level.
// This reads the EFFECTIVE resolved color, never a mock.
void main() {
  Widget host(ThemeData theme) => ProviderScope(
        overrides: [
          plateScannerProvider.overrideWithValue(PlateScanner()),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: SizedBox()),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> checkContrast(WidgetTester tester, ThemeData theme) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(host(theme));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    showGuessSheet(context);
    await tester.pumpAndSettle();

    final iconCtx = tester.element(find.descendant(
      of: find.byType(OhIconButton),
      matching: find.byType(Icon),
    ));
    final resolved = IconTheme.of(iconCtx).color;
    expect(resolved, isNot(theme.colorScheme.primary),
        reason: 'the snap-your-plate glyph must not paint as the ambient '
            'primary icon color — that is invisible-contrast against the '
            'secondaryContainer fill');
    expect(resolved, theme.colorScheme.onSecondaryContainer);
    await unmount(tester);
  }

  testWidgets('snap-your-plate glyph resolves onSecondaryContainer, light',
      (tester) => checkContrast(tester, AppTheme.light));

  testWidgets('snap-your-plate glyph resolves onSecondaryContainer, dark',
      (tester) => checkContrast(tester, AppTheme.dark));
}
