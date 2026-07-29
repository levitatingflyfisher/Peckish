import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// See groceries_screen_test.dart for the three drift widget-test rules
// (runAsync-seed before pump, UI-state assertions only, unmount not close).

Widget host(AppDatabase db) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The bundled USDA spine is real-async asset I/O that can't finish
        // under fake-async pumps; search results here only assert customs.
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// FAB → + sheet → Quick add dialog.
Future<void> openQuickAdd(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Quick add'));
  await tester.pumpAndSettle();
}

Future<void> enterByLabel(
    WidgetTester tester, String label, String value) async {
  await tester.enterText(
      find.widgetWithText(TextField, label).last, value);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('Quick add offers all four macros, not just protein',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    await openQuickAdd(tester);

    expect(find.widgetWithText(TextField, 'kcal'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Protein g'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Carbs g'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Fat g'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a quick add with all four numbers lands them on the day',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    await openQuickAdd(tester);

    await enterByLabel(tester, 'What was it?', 'Leftover curry');
    await enterByLabel(tester, 'kcal', '400');
    await enterByLabel(tester, 'Protein g', '20');
    await enterByLabel(tester, 'Carbs g', '45');
    await enterByLabel(tester, 'Fat g', '14');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      // Let the handler's real-async db writes finish before fake-async pumps.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // Back on Today: the entry row and the totals chips carry every number.
    expect(find.text('Leftover curry'), findsWidgets);
    expect(find.text('400 kcal'), findsOneWidget);
    expect(find.textContaining('Protein 20g'), findsOneWidget);
    expect(find.textContaining('Carbs 45g'), findsOneWidget);
    expect(find.textContaining('Fat 14g'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Cancel returns to the + sheet instead of closing it',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    await openQuickAdd(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The + sheet is still up (its search field and tiles are visible).
    expect(find.text('Search foods — works offline'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"Remember this food" makes the line findable in search',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    await openQuickAdd(tester);

    await enterByLabel(tester, 'What was it?', 'Grandma rolls');
    await enterByLabel(tester, 'kcal', '180');
    await tester.ensureVisible(find.text('Remember this food'));
    await tester.pump();
    await tester.tap(find.text('Remember this food'));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true,
        reason: 'the remember checkbox should be checked after the tap');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      // Let the handler's real-async db writes finish before fake-async pumps.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // Probes: dialog and sheet must both be gone before we reopen.
    expect(find.text('Log it'), findsNothing,
        reason: 'quick-add dialog should have closed');
    expect(find.text('Search foods — works offline'), findsNothing,
        reason: '+ sheet should have closed after logging');

    // Reopen the sheet and search: the remembered food shows as a custom
    // (home icon) result.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'grandma');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    // Rail chip + today's row (behind the sheet) + the search result.
    expect(find.text('Grandma rolls'), findsNWidgets(3));
    await unmount(tester);
  });
}
