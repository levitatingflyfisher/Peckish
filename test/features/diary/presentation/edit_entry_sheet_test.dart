import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// Tap a logged line to fix it. Fixing the qty rescales the numbers from
// the line's own per-unit shape (the "logged one, ate two" case); typing
// a number directly always wins. Works the same on Today and on any
// history day, because both render the one shared tile.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<void> seed(WidgetTester tester, {String? day}) => tester.runAsync(() {
        final now = DateTime.now();
        final d = day ?? DiaryEntry.dayOf(now);
        final at = DateTime.parse('${d}T08:30:00');
        return DiaryRepository(db).log(DiaryEntry(
          id: 'e-1',
          day: d,
          at: at,
          food: const FoodRef.quick(),
          label: 'Egg burrito',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: const MacroSet(kcal: 249, proteinG: 11),
          source: EntrySource.manual,
          createdAt: at,
        ));
      });

  Widget todayHost() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> enterByLabel(
      WidgetTester tester, String label, String value) async {
    await tester.enterText(find.widgetWithText(TextField, label).last, value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a line opens the sheet on its numbers', (tester) async {
    await seed(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(EntryTile), matching: find.text('Egg burrito')));
    await tester.pumpAndSettle();

    expect(find.text('Fix this line'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Egg burrito'), findsOneWidget);
    expect(find.widgetWithText(TextField, '249'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('fixing the qty rescales, and the day updates on save',
      (tester) async {
    await seed(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(EntryTile), matching: find.text('Egg burrito')));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'Qty', '2');

    expect(find.widgetWithText(TextField, '498'), findsOneWidget,
        reason: 'macros follow the qty from the per-unit shape');

    await save(tester);
    expect(find.text('498 kcal'), findsWidgets,
        reason: 'the totals card and the line both carry the fix');
    expect(find.textContaining('2 × serving'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a typed number always wins over the rescale', (tester) async {
    await seed(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(EntryTile), matching: find.text('Egg burrito')));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'kcal', '300');
    await save(tester);

    expect(find.text('300 kcal'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Cancel walks away without touching the ledger', (tester) async {
    await seed(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(EntryTile), matching: find.text('Egg burrito')));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'kcal', '999');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsWidgets);
    expect(find.text('999 kcal'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a history day line opens the same sheet', (tester) async {
    final now = DateTime.now();
    final yesterday =
        DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - 1));
    await seed(tester, day: yesterday);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
          theme: AppTheme.light, home: HistoryDayScreen(day: yesterday)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(EntryTile), matching: find.text('Egg burrito')));
    await tester.pumpAndSettle();
    expect(find.text('Fix this line'), findsOneWidget);
    await unmount(tester);
  });
}
