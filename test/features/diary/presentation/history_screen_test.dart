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
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// History is the answer to "what happens tomorrow?": nothing disappears.
// Week bars + honest averages over the days you actually logged, a day
// list where a blank day stays visibly blank, and every past day opens
// to its own plate.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  String dayAgo(int n) {
    final now = DateTime.now();
    return DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - n));
  }

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

  Widget host({String location = '/history'}) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: AppTheme.light, home: HistoryScreen(anchorDay: dayAgo(0))),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('bars, honest averages, and day rows from the ledger',
      (tester) async {
    await tester.runAsync(() async {
      final repo = DiaryRepository(db);
      await repo.log(entry('e-1', dayAgo(0),
          const MacroSet(kcal: 500, proteinG: 30)));
      await repo.log(entry('e-2', dayAgo(1),
          const MacroSet(kcal: 700, proteinG: 50)));
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Averages over LOGGED days only — two days, not seven.
    expect(find.textContaining('avg 600 kcal'), findsOneWidget);
    expect(find.textContaining('40g protein'), findsOneWidget);
    // Day rows carry their totals; a blank day shows a dash, not a zero.
    expect(find.text('500 kcal'), findsOneWidget);
    expect(find.text('700 kcal'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('an empty history invites instead of showing empty math',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.textContaining('fills in as you log'), findsOneWidget);
    expect(find.textContaining('avg'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the kcal target draws its line and names itself',
      (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(kcal: 2000), kcalRole: TargetRole.under));
      // The chart only exists once something is logged — an empty week
      // shows the invitation, not bare axes.
      await DiaryRepository(db)
          .log(entry('e-1', dayAgo(0), const MacroSet(kcal: 500)));
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
      await DiaryRepository(db).log(entry('e-1', dayAgo(0),
          const MacroSet(kcal: 1820, proteinG: 82)));
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // kcal view first: compact value label on the bar, no kcal target set.
    expect(find.text('1.8k'), findsOneWidget,
        reason: 'kcal value labels ride their bars, compacted');
    expect(find.textContaining('protein target'), findsNothing);

    await tester.tap(find.text('Protein'));
    await tester.pumpAndSettle();

    expect(find.text('82'), findsOneWidget,
        reason: 'the protein view labels bars in grams');
    expect(find.text('1.8k'), findsNothing,
        reason: 'one axis at a time');
    expect(find.text('≥150g protein target'), findsOneWidget,
        reason: 'the target line wears its role mark, per axis');
    await unmount(tester);
  });

  testWidgets('tapping a bar opens that day', (tester) async {
    final day = dayAgo(1);
    await tester.runAsync(() => DiaryRepository(db).log(entry(
        'e-1', day, const MacroSet(kcal: 700),
        label: 'Bar-tap stew')));

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

    await tester.tap(find.byKey(ValueKey('bar-$day')));
    await tester.pumpAndSettle();
    expect(find.text('Bar-tap stew'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a past day opens to its own plate', (tester) async {
    await tester.runAsync(() => DiaryRepository(db).log(entry(
        'e-1', dayAgo(1), const MacroSet(kcal: 700),
        label: 'Taco night')));

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

    // Today → History → yesterday's row → the plate.
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('700 kcal'));
    await tester.pumpAndSettle();
    expect(find.text('Taco night'), findsOneWidget);
    expect(find.text('700 kcal'), findsOneWidget,
        reason: 'the entry line carries its kcal');
    await unmount(tester);
  });
}
