import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// History is the answer to "what happens tomorrow?": nothing disappears.
// A month at a time — the trend line for the axis you picked, honest
// averages over the days you actually logged, and a calendar whose every
// past cell opens that day's plate. The calendar IS the edit surface, and
// it says so.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  // A pinned mid-month "today" — the screen is calendar-month shaped, so a
  // floating now would put the seeded days in a different month on the 1st.
  const today = '2026-08-14';

  DiaryEntry entry(String id, String day, MacroSet macros, {String? label}) {
    final at = DateTime.parse('${day}T12:00:00');
    return DiaryEntry(
      id: id,
      day: day,
      at: at,
      food: const FoodRef.quick(),
      label: label ?? 'Meal $id',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      source: EntrySource.manual,
      createdAt: at,
    );
  }

  Widget host() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: AppTheme.light, home: const HistoryScreen(today: today)),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the month reads from the ledger: cells, honest averages',
      (tester) async {
    await tester.runAsync(() async {
      final repo = DiaryRepository(db);
      await repo.log(
          entry('e-1', today, const MacroSet(kcal: 500, proteinG: 30)));
      await repo.log(entry(
          'e-2', '2026-08-13', const MacroSet(kcal: 700, proteinG: 50)));
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    // Averages over LOGGED days only — two days, not thirty-one.
    expect(find.textContaining('avg 600 kcal'), findsOneWidget);
    expect(find.textContaining('40g protein'), findsOneWidget);
    // Each logged day's cell carries its own number; blank days carry none.
    expect(find.text('500'), findsOneWidget);
    expect(find.text('700'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an empty month still offers every day to tap', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('fills in as you log'), findsOneWidget);
    expect(find.textContaining('avg'), findsNothing);
    // The calendar is the point — an empty month is exactly when you need
    // to reach back into a day and fix it.
    expect(find.byKey(const ValueKey('day-2026-08-05')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the calendar says out loud that a day can be fixed',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap any day'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the kcal target draws its line and names itself',
      (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(kcal: 2000), kcalRole: TargetRole.under));
      await DiaryRepository(db)
          .log(entry('e-1', today, const MacroSet(kcal: 500)));
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('≤2000 kcal target'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the chart speaks every macro, not just kcal', (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(proteinG: 150))); // floor by default
      await DiaryRepository(db).log(
          entry('e-1', today, const MacroSet(kcal: 1820, proteinG: 82)));
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // kcal view first: the cell compacts four digits, no kcal target set.
    expect(find.text('1.8k'), findsOneWidget);
    expect(find.textContaining('protein target'), findsNothing);

    await tester.tap(find.text('Protein'));
    await tester.pumpAndSettle();

    expect(find.text('82'), findsOneWidget,
        reason: 'the protein view speaks grams');
    expect(find.text('1.8k'), findsNothing, reason: 'one axis at a time');
    expect(find.text('≥150g protein target'), findsOneWidget,
        reason: 'the target line wears its role mark, per axis');
    await unmount(tester);
  });

  testWidgets('a day logged exactly at target sits ON the target line',
      (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db)
          .set(const DailyTargets(values: MacroSet(kcal: 2000)));
      final repo = DiaryRepository(db);
      await repo.log(entry('e-1', today, const MacroSet(kcal: 2000)));
      await repo.log(
          entry('e-2', '2026-08-13', const MacroSet(kcal: 1000)));
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final line = tester.getRect(find.byKey(const ValueKey('target-line')));
    final atTarget =
        tester.getRect(find.byKey(const ValueKey('point-2026-08-14')));
    final half = tester.getRect(find.byKey(const ValueKey('point-2026-08-13')));
    final floor = tester.getRect(find.byKey(const ValueKey('chart-floor')));

    // Points and the line share ONE coordinate frame: a day logged at
    // exactly the target sits on the line, not a band above or below it.
    expect((atTarget.center.dy - line.center.dy).abs(), lessThanOrEqualTo(2.0),
        reason: 'a point at exactly the target must sit on the target line');
    // And the frame is linear: half the value is halfway up from the floor.
    expect(
        (floor.center.dy - half.center.dy),
        closeTo((floor.center.dy - atTarget.center.dy) / 2, 2.0),
        reason: 'a mid-fraction day scales within the same frame');
    await unmount(tester);
  });

  testWidgets('the axis picker survives 320dp at 2.5 text scale',
      (tester) async {
    // The fleet's recurring accessibility bug: rigid rows overflow at
    // large text scale on narrow phones. Four segments is a rigid row, and
    // a seven-column calendar is another.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => DiaryRepository(db)
        .log(entry('e-1', today, const MacroSet(kcal: 500))));

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.5),
          ),
          child: HistoryScreen(today: today),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'no layout exception at 320dp / 2.5x text');
    expect(tester.getRect(find.byType(SegmentedButton<String>)).width,
        lessThanOrEqualTo(320),
        reason: 'the picker fits the narrow screen');
    for (final label in const ['kcal', 'Protein', 'Carbs', 'Fat']) {
      expect(tester.getRect(find.text(label)).height, lessThanOrEqualTo(60),
          reason: '"$label" must stay a one-line label');
    }

    // …and stays live: switching to Fat re-labels the cells (no fat was
    // logged, so the kcal value goes away). At this text size the calendar
    // sits below the fold, so scroll to it like a person would.
    final list = find.byType(Scrollable).first;
    Future<void> toCalendar() => tester.scrollUntilVisible(
        find.byKey(const ValueKey('day-$today')), 200,
        scrollable: list);
    Future<void> toPicker() => tester.scrollUntilVisible(
        find.text('Fat'), -200,
        scrollable: list);

    await toCalendar();
    expect(find.text('500'), findsOneWidget);
    await toPicker();
    await tester.tap(find.text('Fat'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await toCalendar();
    expect(find.text('500'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the arrows walk back through months and stop at this one',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(find.byKey(const ValueKey('month-next')))
        .onPressed, isNull,
        reason: 'there is no forward from the month you are living in');

    await tester.tap(find.byKey(const ValueKey('month-prev')));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('month-next')))
        .onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('month-next')));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('days that have not happened yet are shown but not tappable',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The 20th is in the pinned month but after the pinned today.
    final future = tester.widget<InkWell>(find.descendant(
        of: find.byKey(const ValueKey('day-2026-08-20')),
        matching: find.byType(InkWell)));
    expect(future.onTap, isNull,
        reason: 'tomorrow is the Plan tab; History never writes ahead');
    final past = tester.widget<InkWell>(find.descendant(
        of: find.byKey(const ValueKey('day-2026-08-13')),
        matching: find.byType(InkWell)));
    expect(past.onTap, isNotNull);
    await unmount(tester);
  });

  testWidgets('tapping a day cell opens that day', (tester) async {
    final day = DiaryEntry.dayOf(
        DateTime.now().subtract(const Duration(days: 1)));
    await tester.runAsync(() => DiaryRepository(db).log(entry(
        'e-1', day, const MacroSet(kcal: 700),
        label: 'Calendar stew')));

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();

    // The real screen runs on the real clock — yesterday is in the month it
    // opens on unless today is the 1st, in which case step back one month.
    if (find.byKey(ValueKey('day-$day')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('month-prev')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(ValueKey('day-$day')));
    await tester.pumpAndSettle();
    // Scoped to the ledger: the day also carries a regulars rail, where
    // this food now rightly appears as a one-tap chip.
    expect(
        find.descendant(
            of: find.byType(EntryTile), matching: find.text('Calendar stew')),
        findsOneWidget);
    await unmount(tester);
  });
}
