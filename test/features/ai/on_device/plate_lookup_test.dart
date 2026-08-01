import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/on_device/plate_lookup.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';

// The adapter between a plate label's search term and the bundled spine:
// best hit → its first household portion (or 100 g when none is recorded)
// → absolute macros for that portion. A term with no hit is null — the
// draft simply doesn't happen.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usdaFoods).insert(UsdaFoodsCompanion.insert(
          fdcId: const Value(1),
          source: 'sr',
          name: 'Pizza, cheese, regular crust',
          nameNorm: 'pizza, cheese, regular crust',
          kcal: const Value(266),
          proteinG: const Value(11.4),
          carbG: const Value(33.3),
          fatG: const Value(9.7),
        ));
    await db.into(db.usdaPortions).insert(
        UsdaPortionsCompanion.insert(fdcId: 1, label: '1 slice', grams: 107));
    await db.into(db.usdaFoods).insert(UsdaFoodsCompanion.insert(
          fdcId: const Value(2),
          source: 'sr',
          name: 'Egg, whole, cooked',
          nameNorm: 'egg, whole, cooked',
          kcal: const Value(155),
          proteinG: const Value(12.6),
        ));
  });

  tearDown(() => db.close());

  test('a hit resolves to its portion with portion-scaled macros', () async {
    final match = await plateLookup(UsdaFoodRepository(db), 'pizza');

    expect(match, isNotNull);
    expect(match!.name, 'Pizza, cheese, regular crust');
    expect(match.grams, 107);
    expect(match.macros.kcal, closeTo(266 * 1.07, 0.1),
        reason: 'per-100g macros scaled to the portion');
  });

  test('a food with no recorded portion defaults to 100 g', () async {
    final match = await plateLookup(UsdaFoodRepository(db), 'egg');

    expect(match!.grams, 100);
    expect(match.macros.kcal, 155);
  });

  test('no hit → null, never a fabricated match', () async {
    expect(await plateLookup(UsdaFoodRepository(db), 'sushi'), isNull);
  });
}
