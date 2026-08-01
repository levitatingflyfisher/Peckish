import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/settings/presentation/privacy_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// The WeatherGlass pattern, ported: one screen that maps every network
// touch the app can make, so "it worked with data off" is legible truth
// instead of a surprise. The map is the contract — every flow that can
// leave the device is named, and everything else is named as staying.
void main() {
  testWidgets('the map names every flow, honestly', (tester) async {
    // The map grew past the default 600px viewport; a taller surface keeps
    // every ListView row built so the whole contract is assertable.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const PrivacyScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('What leaves your device'), findsOneWidget);
    // The offline spine — the reason data-off just works.
    expect(find.textContaining('bundled'), findsWidgets);
    // The barcode row tells the ADR-0010 truth: scans are answered on the
    // phone; the network waits for an explicit ask.
    expect(find.textContaining('answered on the phone'), findsOneWidget);
    expect(find.textContaining('Ask openfoodfacts.org'), findsOneWidget);
    // Every network touch, named with its trigger — including the
    // database download itself.
    expect(find.textContaining('openfoodfacts.org'), findsWidgets);
    expect(find.textContaining('github.com'), findsOneWidget);
    expect(find.textContaining('huggingface.co'), findsOneWidget);
    expect(find.textContaining('recipe'), findsWidgets);
    // The on-device story, including the Play-services honesty.
    expect(find.textContaining('Google Play services'), findsOneWidget);
    expect(find.textContaining('nothing leaves'), findsWidgets);
    // The stove tier: a home server, named with its encryption and its
    // trigger like every other row.
    expect(find.textContaining('home stove'), findsOneWidget);
    expect(
        find.textContaining('encrypted to your own machine'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });
}
