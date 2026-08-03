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
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The card's contract: it speaks only when it can help (ideas), says a
// finished day is finished, disappears for the day when dismissed, and
// the Settings switch turns the whole feature off. Advisory, never a
// scold: an over-target day renders NO card at all.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget todayHost() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> seedProteinFloorAndEggs(WidgetTester tester) =>
      tester.runAsync(() async {
        await TargetsRepository(db)
            .set(const DailyTargets(values: MacroSet(proteinG: 40)));
        await FoodUsageRepository(db).put(FoodUsage(
          identityKey: 'q:egg',
          food: const FoodRef.quick(),
          label: 'Egg',
          qty: 1,
          unitLabel: 'egg',
          grams: null,
          macros: const MacroSet(kcal: 90, proteinG: 13),
          useCount: 12,
          lastUsedAt: DateTime.utc(2026, 7, 28),
          hidden: false,
        ));
      });

  testWidgets('a short day proposes from the regulars, and Log lands it',
      (tester) async {
    await seedProteinFloorAndEggs(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    expect(find.text('Round out your day'), findsOneWidget);
    expect(find.textContaining('3 × Egg'), findsOneWidget,
        reason: '3 × 13g closes a 40g floor');

    await tester.runAsync(() async {
      await tester.tap(find.text('Log'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // The combo landed as one diary line, and the day is now finished —
    // the card says so instead of proposing more.
    expect(find.textContaining('Egg'), findsWidgets);
    expect(find.textContaining("You're set for today"), findsOneWidget);
    expect(find.text('Log'), findsNothing);
    await unmount(tester);
  });

  testWidgets('dismiss hides the card for the rest of the day', (tester) async {
    await seedProteinFloorAndEggs(tester);
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Hide for today'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Round out your day'), findsNothing);
    await unmount(tester);
  });

  testWidgets('no targets → no card at all', (tester) async {
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();
    expect(find.text('Round out your day'), findsNothing);
    expect(find.textContaining("You're set"), findsNothing);
    await unmount(tester);
  });

  testWidgets('a finished day gets the set line, not more food',
      (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db)
          .set(const DailyTargets(values: MacroSet(proteinG: 40)));
      final now = DateTime.now();
      await DiaryRepository(db).log(DiaryEntry(
        id: 'e-1',
        day: DiaryEntry.dayOf(now),
        at: now,
        food: const FoodRef.quick(),
        label: 'Big lunch',
        qty: 1,
        unitLabel: 'serving',
        grams: null,
        macros: const MacroSet(kcal: 700, proteinG: 45),
        source: EntrySource.manual,
        createdAt: now,
      ));
    });

    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    expect(find.textContaining("You're set for today"), findsOneWidget);
    expect(find.text('Log'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the Settings switch turns the feature off everywhere',
      (tester) async {
    await seedProteinFloorAndEggs(tester);
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
    expect(find.text('Round out your day'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester
          .tap(find.widgetWithText(SwitchListTile, 'Round out your day'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Round out your day'), findsNothing,
        reason: 'the off switch is the off switch');
    await unmount(tester);
  });
}
