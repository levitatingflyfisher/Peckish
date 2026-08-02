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
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child:
          MaterialApp(theme: AppTheme.light, home: const PrivacyScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('What leaves your device'), findsOneWidget);
    // The offline spine — the reason data-off just works.
    expect(find.textContaining('bundled'), findsWidgets);
    // Every network touch, named with its trigger.
    expect(find.textContaining('openfoodfacts.org'), findsOneWidget);
    expect(find.textContaining('huggingface.co'), findsOneWidget);
    expect(find.textContaining('recipe'), findsWidgets);
    // The on-device story, including the Play-services honesty.
    expect(find.textContaining('Google Play services'), findsOneWidget);
    expect(find.textContaining('nothing leaves'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  });
}
