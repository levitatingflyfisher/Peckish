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
import 'package:peckish/features/diary/presentation/regulars_rail.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The v0.8 phone test: "I can't seem to use My Foods lookups in the history
// the way I can quickly add them for today's date." Logging a food you have
// logged before is THE most common way to add anything — it must cost one
// tap on every day, not just on today.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  String dayBefore(int n) {
    final now = DateTime.now();
    return DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - n));
  }

  /// Make 'Porridge' a regular by logging it — the single write path means
  /// any log anywhere records the habit.
  Future<void> seedRegular(WidgetTester tester) => tester.runAsync(() async {
        final at = DateTime.now().subtract(const Duration(days: 3));
        await DiaryRepository(db).log(DiaryEntry(
          id: 'seed',
          day: DiaryEntry.dayOf(at),
          at: at,
          food: const FoodRef.custom('porridge'),
          label: 'Porridge',
          qty: 1,
          unitLabel: 'bowl',
          grams: null,
          macros: const MacroSet(kcal: 320, proteinG: 11),
          source: EntrySource.tap,
          createdAt: at,
        ));
      });

  Widget host(Widget home) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
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

  testWidgets('a past day carries its own regulars rail — one tap, no sheet',
      (tester) async {
    await seedRegular(tester);
    final day = dayBefore(1);
    await tester.pumpWidget(host(HistoryDayScreen(day: day)));
    await settle(tester);

    expect(find.text('Your regulars'), findsOneWidget,
        reason: 'the fastest way to add is the one you always reach for');

    await tester.tap(find.widgetWithText(ActionChip, 'Porridge'));
    await settle(tester);

    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsOneWidget,
      reason: 'one tap on a past day lands a line on THAT day',
    );
    await unmount(tester);
  });

  testWidgets("a past day's + sheet offers the regulars too", (tester) async {
    await seedRegular(tester);
    await tester.pumpWidget(host(HistoryDayScreen(day: dayBefore(2))));
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    expect(find.text('Your regulars'), findsWidgets,
        reason: 'the + sheet is the one add surface present on every day');
    await tester.tap(find.widgetWithText(ListTile, 'Porridge'));
    await settle(tester);

    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsOneWidget,
    );
    await unmount(tester);
  });

  test('See all from a past day carries that day in the route', () {
    // The screen honours ?day=; this pins the other half — that a past
    // day's rail actually puts one there. Both halves have to hold or the
    // fix only works in the test that constructs the screen directly.
    expect(foodsPathForDay(null), '/foods');
    expect(foodsPathForDay('2026-07-30'), '/foods?day=2026-07-30');
  });

  testWidgets('the Foods screen logs to the day it was opened from',
      (tester) async {
    // The v0.9 phone test: the rail landed on the right day, but 'See all'
    // opened /foods with no day at all, so every tap there fell on today.
    // Assert on the PERSISTED row, not on what the screen shows — the rail
    // already passes a day, so a test of the rule would go green for free.
    await seedRegular(tester);
    final day = dayBefore(5);
    await tester.pumpWidget(host(FoodsScreen(day: day)));
    await settle(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Porridge').first);
    await settle(tester);

    final logged =
        await tester.runAsync(() => DiaryRepository(db).entriesForDay(day))
            as List<DiaryEntry>;
    expect(logged.map((e) => e.label), contains('Porridge'),
        reason: 'a tap on the Foods screen reached from a past day belongs '
            'to THAT day');

    final today = await tester.runAsync(() =>
            DiaryRepository(db).entriesForDay(DiaryEntry.dayOf(DateTime.now())))
        as List<DiaryEntry>;
    expect(today, isEmpty, reason: 'and today must be left alone');
    await unmount(tester);
  });

  testWidgets('a regular logged onto a past day never touches today',
      (tester) async {
    await seedRegular(tester);
    await tester.pumpWidget(host(HistoryDayScreen(day: dayBefore(4))));
    await settle(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Porridge'));
    await settle(tester);
    await unmount(tester);

    await tester.pumpWidget(host(const TodayScreen()));
    await settle(tester);
    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsNothing,
      reason: "a fix to a day four days back is not one of today's lines",
    );
    await unmount(tester);
  });

  testWidgets("today's rail still lands on today", (tester) async {
    await seedRegular(tester);
    await tester.pumpWidget(host(const TodayScreen()));
    await settle(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Porridge'));
    await settle(tester);

    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsOneWidget,
    );
    await unmount(tester);
  });
}
