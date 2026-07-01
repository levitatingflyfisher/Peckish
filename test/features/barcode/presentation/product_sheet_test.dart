import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The sheet is confirm-before-commit: nothing touches the ledger until the
// user taps Log, and what lands is a SNAPSHOT scaled to the grams they
// confirmed.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const nutella = OffProduct(
    barcode: '3017620422003',
    name: 'Nutella',
    brand: 'Ferrero',
    per100g: MacroSet(kcal: 539, proteinG: 6.3, carbG: 57.5, fatG: 30.9),
    servingLabel: '15 g',
    servingGrams: 15,
  );

  Widget host() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> openSheet(WidgetTester tester, OffProduct product) async {
    final context = tester.element(find.byType(TodayScreen));
    showProductSheet(context, product);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shows the product, defaults to the label serving, and scales',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openSheet(tester, nutella);

    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    // Serving default: 15 g of 539/100g ≈ 81 kcal.
    expect(find.textContaining('81 kcal'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('539 kcal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Log writes a scan-sourced snapshot onto Today', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openSheet(tester, nutella);

    await tester.tap(find.text('Log it'));
    await tester.pumpAndSettle();

    // Sheet closed; the entry appears on Today underneath with the scaled
    // snapshot — twice, in fact: the ledger row AND the recents chip the
    // log just earned (UI-state assertion, per the rules).
    expect(find.text('Log it'), findsNothing);
    expect(find.text('Nutella (Ferrero)'), findsNWidgets(2));
    expect(find.textContaining('81 kcal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('unknown macros stay unknown on the way through', (tester) async {
    const mystery = OffProduct(
      barcode: '96385074',
      name: 'Mystery drink',
      brand: null,
      per100g: MacroSet(kcal: 45),
      servingLabel: null,
      servingGrams: null,
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openSheet(tester, mystery);

    // No serving info → defaults to 100 g.
    expect(find.textContaining('45 kcal'), findsOneWidget);
    // The sheet is honest about what the label didn't say.
    expect(find.textContaining('protein —'), findsOneWidget);
    await unmount(tester);
  });
}
