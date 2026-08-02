import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/settings/data/export_serializer.dart';

PeckishExport fullExport() => PeckishExport(
      createdAt: DateTime.utc(2026, 7, 25, 18),
      customFoods: [
        CustomFood(
          id: 'cf-1',
          name: 'Cafe Rio salad',
          servingLabel: '1 salad',
          perServing: const MacroSet(kcal: 640, proteinG: 42),
          createdAt: DateTime.utc(2026, 7, 1),
          archived: false,
        ),
        CustomFood(
          id: 'cf-2',
          name: 'Spam',
          servingLabel: '2 slices',
          perServing: const MacroSet(kcal: 360),
          createdAt: DateTime.utc(2026, 7, 2),
          barcode: '27000612323',
        ),
      ],
      diaryEntries: [
        DiaryEntry(
          id: 'e-1',
          day: '2026-07-25',
          at: DateTime.utc(2026, 7, 25, 12, 30),
          food: const FoodRef.usda(2707343),
          label: 'Egg burrito',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: const MacroSet(kcal: 249, proteinG: 10.9),
          source: EntrySource.search,
          createdAt: DateTime.utc(2026, 7, 25, 12, 30),
        ),
      ],
      savedMeals: [
        SavedMeal(
          id: 'm-1',
          name: 'Panda — bad day',
          position: 0,
          createdAt: DateTime.utc(2026, 7, 2),
          lastUsedAt: DateTime.utc(2026, 7, 24, 18),
          items: [
            const SavedMealItem(
              id: 'i-1',
              food: FoodRef.custom('cf-1'),
              label: 'Orange chicken',
              qty: 1,
              unitLabel: 'serving',
              grams: null,
              macros: MacroSet(kcal: 490),
            ),
          ],
        ),
      ],
      recipes: [
        Recipe(
          id: 'r-1',
          title: 'Weeknight Tacos',
          servings: 4,
          sourceUrl: 'https://example.com/tacos',
          instructions: 'Brown the beef.',
          declaredPerServing: const MacroSet(kcal: 300),
          createdAt: DateTime.utc(2026, 7, 3),
          ingredients: const [
            RecipeIngredient(
              id: 'ri-1',
              text: '1 lb ground beef',
              food: FoodRef.usda(171077),
              grams: 454,
              macros: MacroSet(kcal: 1150, proteinG: 78),
            ),
            RecipeIngredient(id: 'ri-2', text: '8 corn tortillas'),
          ],
        ),
      ],
      planEntries: const [
        PlanEntry(
          id: 'p-1',
          day: '2026-07-27',
          slot: PlanSlot.dinner,
          kind: PlanKind.recipe,
          refId: 'r-1',
        ),
        PlanEntry(
          id: 'p-2',
          day: '2026-07-29',
          slot: PlanSlot.dinner,
          kind: PlanKind.note,
          note: 'Leftovers',
        ),
      ],
      groceryItems: [
        GroceryItem(
          id: 'g-1',
          name: '2× 1 onion',
          aisle: GroceryAisle.produce,
          checked: true,
          manual: false,
          sourceRecipeId: 'r-1',
          createdAt: DateTime.utc(2026, 7, 25),
        ),
      ],
      foodUsages: [
        FoodUsage(
          identityKey: 'q:oatmeal',
          food: const FoodRef.quick(),
          label: 'Oatmeal',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: const MacroSet(kcal: 150, proteinG: 5),
          useCount: 17,
          lastUsedAt: DateTime.utc(2026, 7, 25, 8),
          hidden: true,
        ),
      ],
      targets: const DailyTargets(
        values: MacroSet(kcal: 3200, proteinG: 180),
        kcalRole: TargetRole.under,
      ),
    );

void main() {
  test('encode → decode round-trips every section', () {
    final decoded = PeckishExport.fromJson(fullExport().toPrettyJson());

    expect(decoded.customFoods.first.name, 'Cafe Rio salad');
    expect(decoded.customFoods.first.perServing.kcal, 640);
    expect(decoded.customFoods.first.perServing.carbG, isNull);
    // A restored food must still answer its own barcode, or the restore
    // quietly costs you every one-tap scan you had built up.
    expect(decoded.customFoods.last.barcode, '27000612323');
    expect(decoded.customFoods.first.barcode, isNull);

    final e = decoded.diaryEntries.single;
    expect(e.food.kind, FoodKind.usda);
    expect(e.food.usdaFdcId, 2707343);
    expect(e.day, '2026-07-25');
    expect(e.source, EntrySource.search);

    final m = decoded.savedMeals.single;
    expect(m.name, 'Panda — bad day');
    expect(m.items.single.food.customFoodId, 'cf-1');
    expect(m.lastUsedAt, DateTime.utc(2026, 7, 24, 18));

    final r = decoded.recipes.single;
    expect(r.title, 'Weeknight Tacos');
    expect(r.declaredPerServing!.kcal, 300);
    expect(r.ingredients, hasLength(2));
    expect(r.ingredients.first.food!.usdaFdcId, 171077);
    expect(r.ingredients.last.food, isNull);
    expect(r.ingredients.last.macros, isNull);

    expect(decoded.planEntries, hasLength(2));
    expect(decoded.planEntries.first.slot, PlanSlot.dinner);
    expect(decoded.planEntries.last.note, 'Leftovers');
    final g = decoded.groceryItems.single;
    expect(g.aisle, GroceryAisle.produce);
    expect(g.checked, isTrue);
    expect(g.sourceRecipeId, 'r-1');

    // Regulars: counts + hidden flags are truth from the file, and the
    // identityKey is re-derived from the food ref, never stored twice.
    final u = decoded.foodUsages.single;
    expect(u.identityKey, 'q:oatmeal');
    expect(u.useCount, 17);
    expect(u.hidden, isTrue);
    expect(u.lastUsedAt, DateTime.utc(2026, 7, 25, 8));
    expect(u.macros.kcal, 150);

    expect(decoded.targets.values.kcal, 3200);
    expect(decoded.targets.values.fatG, isNull);
    expect(decoded.targets.kcalRole, TargetRole.under,
        reason: 'roles ride in the targets object as additive keys');
    expect(decoded.targets.proteinRole, isNull);
  });

  test('a pre-roles targets object decodes with null roles (defaults apply)',
      () {
    final decoded = PeckishExport.fromJson(
        '{"app":"peckish","schemaVersion":1,'
        '"targets":{"kcal":2000,"proteinG":150}}');
    expect(decoded.targets.values.kcal, 2000);
    expect(decoded.targets.kcalRole, isNull);
    expect(decoded.targets.resolvedProteinRole, TargetRole.atLeast);
  });

  test('an export with absent sections decodes to empties (old files restore)',
      () {
    final decoded = PeckishExport.fromJson(
        '{"app":"peckish","schemaVersion":1}');
    expect(decoded.customFoods, isEmpty);
    expect(decoded.diaryEntries, isEmpty);
    expect(decoded.savedMeals, isEmpty);
    expect(decoded.recipes, isEmpty);
    expect(decoded.planEntries, isEmpty);
    expect(decoded.groceryItems, isEmpty);
    expect(decoded.foodUsages, isEmpty,
        reason: 'a v0.2 export has no regulars section — restores fine');
    expect(decoded.targets.values.kcal, isNull);
  });

  test('a different app or a future schema refuses', () {
    expect(() => PeckishExport.fromJson('{"app":"lullaby","schemaVersion":1}'),
        throwsFormatException);
    expect(() => PeckishExport.fromJson('{"app":"peckish","schemaVersion":99}'),
        throwsFormatException);
  });

  test('export filename is date-stamped', () {
    expect(exportFileName(DateTime(2026, 7, 25)),
        'peckish-export-2026-07-25.json');
  });

  test('a scan-sourced entry round-trips, and unknown sources degrade to '
      'manual (older app reading a newer file)', () {
    final export = PeckishExport(
      createdAt: DateTime.utc(2026, 7, 26),
      diaryEntries: [
        DiaryEntry(
          id: 'e-scan',
          day: '2026-07-26',
          at: DateTime.utc(2026, 7, 26, 9),
          food: const FoodRef.quick(),
          label: 'Nutella (Ferrero)',
          qty: 15,
          unitLabel: 'g',
          grams: 15,
          macros: const MacroSet(kcal: 81),
          source: EntrySource.scan,
          createdAt: DateTime.utc(2026, 7, 26, 9),
        ),
      ],
    );
    final decoded = PeckishExport.fromJson(export.toPrettyJson());
    expect(decoded.diaryEntries.single.source, EntrySource.scan);

    final foreign = export
        .toPrettyJson()
        .replaceAll('"source": "scan"', '"source": "hologram"');
    expect(PeckishExport.fromJson(foreign).diaryEntries.single.source,
        EntrySource.manual);
  });
}
