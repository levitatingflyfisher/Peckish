import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// Lens audit finding 4: the plan never fed the diary, so "that's what we
// had" meant searching for it again. Today's planned recipes and meals get
// an explicit "Log this" (one tap, with the lasting Undo); nothing is ever
// logged on its own.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  final today = DiaryEntry.dayOf(DateTime.now());
  final tomorrow =
      DiaryEntry.dayOf(DateTime.now().add(const Duration(days: 1)));

  Future<void> pumpPlan(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: const PlanScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<List<DiaryEntry>> logged() => DiaryRepository(db).entriesForDay(today);

  testWidgets('Log this puts one serving of today\'s recipe in the diary; '
      'Undo takes it out', (tester) async {
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Roast chicken',
        servings: 4,
        declaredPerServing: const MacroSet(kcal: 620, proteinG: 48),
        createdAt: DateTime(2026, 7, 25),
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: today,
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
      // Only today's rows offer it: tomorrow has not been eaten yet.
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-2',
        day: tomorrow,
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-3',
        day: today,
        slot: PlanSlot.lunch,
        kind: PlanKind.note,
        note: 'Pizza out',
      ));
    });
    await pumpPlan(tester);

    expect(find.text('Log this'), findsOneWidget,
        reason: 'today\'s recipe only: not tomorrow\'s, not a note');
    expect(await tester.runAsync(logged), isEmpty,
        reason: 'nothing is logged on its own');

    await tester.runAsync(() async {
      await tester.tap(find.text('Log this'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final entries = (await tester.runAsync(logged))!;
    expect(entries, hasLength(1));
    expect(entries.single.label, 'Roast chicken');
    expect(entries.single.qty, 1);
    expect(entries.single.unitLabel, 'serving');
    expect(entries.single.macros.kcal, 620);
    expect(find.text('Logged Roast chicken'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(logged), isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a recipe with no known nutrition logs with blanks, not zeros',
      (tester) async {
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-2',
        title: 'Soup',
        servings: 2,
        createdAt: DateTime(2026, 7, 25),
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: today,
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-2',
      ));
    });
    await pumpPlan(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Log this'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final entries = (await tester.runAsync(logged))!;
    expect(entries.single.label, 'Soup');
    expect(entries.single.macros.kcal, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a planned staple logs every item; Undo takes them all out',
      (tester) async {
    await tester.runAsync(() async {
      await SavedMealRepository(db).create(SavedMeal(
        id: 'm-1',
        name: 'Taco night',
        position: 0,
        createdAt: DateTime(2026, 7, 25),
        items: [
          for (final (label, kcal) in [('Tacos', 600.0), ('Salsa', 40.0)])
            SavedMealItem(
              id: 'i-$label',
              food: const FoodRef.quick(),
              label: label,
              qty: 1,
              unitLabel: 'serving',
              grams: null,
              macros: MacroSet(kcal: kcal),
            ),
        ],
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: today,
        slot: PlanSlot.dinner,
        kind: PlanKind.meal,
        refId: 'm-1',
      ));
    });
    await pumpPlan(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Log this'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect((await tester.runAsync(logged))!.map((e) => e.label).toSet(),
        {'Tacos', 'Salsa'});
    expect(find.text('Logged Taco night'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(await tester.runAsync(logged), isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Log this fits beside a long name at 320dp up to 3x text',
      (tester) async {
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Grandma Rosa\'s Sunday roast chicken with lemon',
        servings: 4,
        declaredPerServing: const MacroSet(kcal: 620),
        createdAt: DateTime(2026, 7, 25),
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: today,
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
    });
    await runA11ySweep(
      tester,
      logicalSize: const Size(320, 4000),
      textScales: const [1.0, 2.0, 3.0],
      pumpScreen: () => tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => UndoHost(child: child!),
          home: const PlanScreen(),
        ),
      )),
      interact: () async {
        expect(find.text('Log this').hitTestable(), findsOneWidget);
      },
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
