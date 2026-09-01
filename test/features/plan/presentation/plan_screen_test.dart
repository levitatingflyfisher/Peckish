import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// The × beside a planned meal is a deliberate tap: it removes at once and
// hands the entry back through the lasting Undo (fleet delete ruling).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('Remove takes the entry off the day; Undo puts it back',
      (tester) async {
    // Tall enough that every day of the week is built, whichever day
    // today is.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => PlanRepository(db).upsert(PlanEntry(
          id: 'p-1',
          day: DiaryEntry.dayOf(DateTime.now()),
          slot: PlanSlot.dinner,
          kind: PlanKind.note,
          note: 'Leftovers',
        )));
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: const PlanScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Leftovers'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Remove Leftovers'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Leftovers'), findsNothing);
    expect(find.text('Removed Leftovers'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Leftovers'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a planned recipe shows its kcal per serving', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Roast chicken',
        servings: 4,
        declaredPerServing: const MacroSet(kcal: 620),
        createdAt: DateTime(2026, 7, 25),
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: DiaryEntry.dayOf(DateTime.now()),
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const PlanScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Roast chicken'), findsOneWidget);
    expect(find.text('620 kcal per serving'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
