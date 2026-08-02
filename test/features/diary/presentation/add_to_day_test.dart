import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// A missed day is fixable: any history day carries a + that adds TO THAT
// DAY, by every route in — search, quick add, saved meals, barcode, AI.
// The sheet says which day it's feeding; today's sheet is exactly what it
// always was.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  String yesterday() {
    final now = DateTime.now();
    return DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - 1));
  }

  Widget dayHost(String day) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(
            theme: AppTheme.light, home: HistoryDayScreen(day: day)),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the + on a past day quick-adds to THAT day', (tester) async {
    final day = yesterday();
    await tester.pumpWidget(dayHost(day));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Adding to'), findsOneWidget,
        reason: 'the sheet says which day it feeds');
    expect(find.text('Scan a barcode'), findsOneWidget,
        reason: 'a tin in the recycling is exactly how you fix a missed day');

    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'What was it?').last, 'Forgotten stew');
    await tester.enterText(
        find.widgetWithText(TextField, 'kcal').last, '450');
    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(EntryTile), matching: find.text('Forgotten stew')),
        findsOneWidget,
        reason: 'the line lands on the open history day');
    expect(find.text('450 kcal'), findsOneWidget);
    await unmount(tester);

    // And today stays clean — the entry went to yesterday, not now.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
    ));
    await tester.pumpAndSettle();
    // The regulars RAIL may (rightly) show the food — logging to any day
    // records the habit. What must NOT exist is a diary LINE for today.
    expect(find.descendant(
            of: find.byType(EntryTile),
            matching: find.text('Forgotten stew')),
        findsNothing,
        reason: "yesterday's fix must not appear as one of today's lines");
    await unmount(tester);
  });

  testWidgets("today's + sheet is unchanged: both now-flows present",
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Scan a barcode'), findsOneWidget);
    expect(find.textContaining('Adding to'), findsNothing);
    await unmount(tester);
  });
}
