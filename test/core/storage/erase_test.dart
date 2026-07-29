import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';

void main() {
  test('eraseUserData wipes user tables, keeps the spine and shell prefs',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final usda = UsdaFoodRepository(db);
    await usda.importSpine(jsonEncode({
      'v': 1,
      'foods': [
        [1, 'sr', 'Test food', 100.0, 1.0, 2.0, 3.0, null, null, null],
      ],
      'portions': [],
    }));
    await CustomFoodRepository(db).create(CustomFood(
      id: 'cf-1',
      name: 'Custom',
      servingLabel: '1 serving',
      perServing: const MacroSet(kcal: 100),
      createdAt: DateTime(2026, 7, 25),
    ));
    final diary = DiaryRepository(db);
    await diary.log(DiaryEntry(
      id: 'e-1',
      day: '2026-07-25',
      at: DateTime(2026, 7, 25, 12),
      food: const FoodRef.quick(),
      label: 'Something',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: const MacroSet(kcal: 500),
      source: EntrySource.manual,
      createdAt: DateTime(2026, 7, 25, 12),
    ));
    final meals = SavedMealRepository(db);
    await meals.create(SavedMeal(
      id: 'm-1',
      name: 'Meal',
      position: 0,
      createdAt: DateTime(2026, 7, 25),
      items: [
        const SavedMealItem(
          id: 'i-1',
          food: FoodRef.quick(),
          label: 'Item',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: MacroSet(kcal: 100),
        ),
      ],
    ));
    final recipes = RecipeRepository(db);
    await recipes.create(Recipe(
      id: 'r-1',
      title: 'Tacos',
      servings: 4,
      createdAt: DateTime(2026, 7, 25),
      ingredients: const [RecipeIngredient(id: 'ri-1', text: '1 onion')],
    ));
    await PlanRepository(db).upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-27',
      slot: PlanSlot.dinner,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    final groceries = GroceryRepository(db);
    await groceries.addManual('Milk');
    await TargetsRepository(db)
        .set(const DailyTargets(values: MacroSet(kcal: 3200)));
    await db.into(db.userPrefs).insertOnConflictUpdate(
        UserPrefsCompanion.insert(key: 'theme', value: 'dark'));

    await db.eraseUserData();

    expect(await diary.entriesForDay('2026-07-25'), isEmpty);
    expect(await CustomFoodRepository(db).getAll(includeArchived: true),
        isEmpty);
    expect(await meals.getAll(includeArchived: true), isEmpty);
    expect(await recipes.getAll(includeArchived: true), isEmpty);
    expect(await PlanRepository(db).entriesForDays(['2026-07-27']), isEmpty);
    expect(await groceries.getAll(), isEmpty);
    expect(await FoodUsageRepository(db).getAll(), isEmpty,
        reason: 'the regulars record is user data — erase means erase');
    expect((await TargetsRepository(db).get()).values.kcal, isNull);
    // reference spine and shell prefs survive
    expect(await usda.byId(1), isNotNull);
    final theme = await (db.select(db.userPrefs)
          ..where((p) => p.key.equals('theme')))
        .getSingleOrNull();
    expect(theme?.value, 'dark');
  });
}
