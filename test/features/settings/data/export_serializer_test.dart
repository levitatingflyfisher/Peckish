import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
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
      targets: const MacroSet(kcal: 3200, proteinG: 180),
    );

void main() {
  test('encode → decode round-trips every section', () {
    final decoded = PeckishExport.fromJson(fullExport().toPrettyJson());

    expect(decoded.customFoods.single.name, 'Cafe Rio salad');
    expect(decoded.customFoods.single.perServing.kcal, 640);
    expect(decoded.customFoods.single.perServing.carbG, isNull);

    final e = decoded.diaryEntries.single;
    expect(e.food.kind, FoodKind.usda);
    expect(e.food.usdaFdcId, 2707343);
    expect(e.day, '2026-07-25');
    expect(e.source, EntrySource.search);

    final m = decoded.savedMeals.single;
    expect(m.name, 'Panda — bad day');
    expect(m.items.single.food.customFoodId, 'cf-1');
    expect(m.lastUsedAt, DateTime.utc(2026, 7, 24, 18));

    expect(decoded.targets.kcal, 3200);
    expect(decoded.targets.fatG, isNull);
  });

  test('an export with absent sections decodes to empties (old files restore)',
      () {
    final decoded = PeckishExport.fromJson(
        '{"app":"peckish","schemaVersion":1}');
    expect(decoded.customFoods, isEmpty);
    expect(decoded.diaryEntries, isEmpty);
    expect(decoded.savedMeals, isEmpty);
    expect(decoded.targets.kcal, isNull);
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
}
