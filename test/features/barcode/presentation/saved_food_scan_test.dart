import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The v0.8 phone test: "I entered a barcode twice in a row and the second
// time it looked it up again even though I said to save the food." The
// checkbox says "so next time is one tap"; these are the tests that make
// that sentence true.
void main() {
  late AppDatabase db;
  var requests = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = 0;
  });

  const nutella = OffProduct(
    barcode: '3017620422003',
    name: 'Nutella',
    brand: 'Ferrero',
    per100g: MacroSet(kcal: 539, proteinG: 6.3, carbG: 57.5, fatG: 30.9),
    servingLabel: '15 g',
    servingGrams: 15,
  );

  // Counts every network attempt; the body never matters, because a passing
  // test must never reach it.
  OffClient countingClient() => OffClient(client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }));

  Widget host(Widget home) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          offClientProvider.overrideWithValue(countingClient()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  testWidgets('ticking Save to My Foods brings the barcode home',
      (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showProductSheet(context, nutella),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to My Foods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log it'));
    await settle(tester);

    final saved = await tester
        .runAsync(() => CustomFoodRepository(db).byBarcode('3017620422003'));
    expect(saved?.name, 'Nutella (Ferrero)',
        reason: 'the food that came off a package remembers which package');
    await unmount(tester);
  });

  testWidgets('the second scan of a saved food logs it — no sheet, no network',
      (tester) async {
    // First time through: save it.
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showProductSheet(context, nutella),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to My Foods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log it'));
    await settle(tester);
    await unmount(tester);

    // Second time through: type the same digits into the scanner.
    await tester.pumpWidget(host(const ScanScreen()));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '3017620422003');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Pumped to the snackbar, not settled through it: pumpAndSettle would
    // run time past its own dismissal and find nothing.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(requests, 0,
        reason: 'Peckish must not ask the network what it already knows');
    expect(find.text('Ask openfoodfacts.org'), findsNothing,
        reason: 'a saved food is not a miss');
    expect(find.textContaining('Logged Nutella'), findsOneWidget,
        reason: 'one action, and it says what it did');

    final entries = (await tester.runAsync(() => DiaryRepository(db)
        .watchEntriesForDay(DiaryEntry.dayOf(DateTime.now()))
        .first))!;
    expect(entries.length, 2,
        reason: 'the first save logged one line, this scan logged the second');
    expect(entries.last.label, 'Nutella (Ferrero)');
    await unmount(tester);
  });

  testWidgets('a saved food scanned for a past day lands on that day',
      (tester) async {
    await tester.runAsync(() => CustomFoodRepository(db).create(CustomFood(
          id: 'nutella',
          name: 'Nutella (Ferrero)',
          servingLabel: '15 g',
          perServing: const MacroSet(kcal: 81),
          createdAt: DateTime(2026, 8, 1),
          barcode: '3017620422003',
        )));

    const day = '2026-07-19';
    await tester.pumpWidget(host(const ScanScreen(day: day)));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '3017620422003');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(requests, 0);
    final entries = (await tester
        .runAsync(() => DiaryRepository(db).watchEntriesForDay(day).first))!;
    expect(entries.single.label, 'Nutella (Ferrero)');
    expect(DiaryEntry.dayOf(entries.single.at), day,
        reason: 'the backdated line resolves back to its own day');
    await unmount(tester);
  });
}
