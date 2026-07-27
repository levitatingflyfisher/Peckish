import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';

// The write-path sync laws for the five household-shared tables:
//  * every write carries a fresh HLC stamp + this node's id,
//  * deletes are tombstones — hidden from every read, present for sync,
//  * derived grocery rows get DETERMINISTIC ids, so two devices
//    regenerating the same plan converge instead of duplicating.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  CustomFood food(String id) => CustomFood(
        id: id,
        name: 'Rolls $id',
        servingLabel: '2 rolls',
        perServing: const MacroSet(kcal: 300),
        createdAt: DateTime(2026),
      );

  group('stamping', () {
    test('creates and updates carry hlc + nodeId', () async {
      final repo = CustomFoodRepository(db);
      await repo.create(food('cf-1'));
      var row = await db.select(db.customFoods).getSingle();
      expect(row.hlc, isNotEmpty);
      expect(row.nodeId, isNotEmpty);
      final firstHlc = row.hlc!;

      await repo.update(food('cf-1').copyWith(name: 'Renamed'));
      row = await db.select(db.customFoods).getSingle();
      expect(row.hlc!.compareTo(firstHlc), greaterThan(0),
          reason: 'a later write must carry a later stamp');
    });
  });

  group('tombstones', () {
    test('a deleted custom food disappears from reads but stays as a '
        'tombstone', () async {
      final repo = CustomFoodRepository(db);
      await repo.create(food('cf-1'));
      await repo.delete('cf-1');

      expect(await repo.getAll(), isEmpty);
      expect(await repo.byId('cf-1'), isNull);

      final raw = await db.select(db.customFoods).getSingle();
      expect(raw.isDeleted, isTrue,
          reason: 'the deletion itself must be able to travel to peers');
      expect(raw.hlc, isNotEmpty);
    });

    test('a removed plan cell tombstones and leaves the visible plan',
        () async {
      final repo = PlanRepository(db);
      await repo.upsert(const PlanEntry(
          id: 'p-1', day: '2026-07-27', slot: PlanSlot.dinner,
          kind: PlanKind.note, note: 'Tacos'));
      await repo.remove('p-1');

      expect(await repo.entriesForDays(['2026-07-27']), isEmpty);
      final raw = await db.select(db.planEntries).getSingle();
      expect(raw.isDeleted, isTrue);
    });

    test('a deleted recipe hides, its plan cell resolves as deleted',
        () async {
      final recipes = RecipeRepository(db);
      await recipes.create(Recipe(
        id: 'r-1',
        title: 'Tacos',
        servings: null,
        createdAt: DateTime(2026),
      ));
      await recipes.delete('r-1');
      expect(await recipes.getAll(), isEmpty);
      expect(await recipes.byId('r-1'), isNull);
      final raw = await db.select(db.recipes).getSingle();
      expect(raw.isDeleted, isTrue);
    });
  });

  group('deterministic grocery ids', () {
    Future<void> seedPlanWithTacos(AppDatabase target) async {
      await RecipeRepository(target).create(Recipe(
        id: 'r-1',
        title: 'Tacos',
        servings: null,
        ingredients: const [
          RecipeIngredient(id: 'i-1', text: '1 onion'),
          RecipeIngredient(id: 'i-2', text: '500 g ground beef'),
        ],
        createdAt: DateTime(2026),
      ));
      await PlanRepository(target).upsert(const PlanEntry(
          id: 'p-1', day: '2026-07-27', slot: PlanSlot.dinner,
          kind: PlanKind.recipe, refId: 'r-1'));
    }

    test('two devices regenerating the same plan mint the same ids',
        () async {
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await seedPlanWithTacos(db);
      await seedPlanWithTacos(other);

      await GroceryRepository(db).regenerateFromPlan(['2026-07-27']);
      await GroceryRepository(other).regenerateFromPlan(['2026-07-27']);

      final a = (await db.select(db.groceryItems).get())
          .map((r) => r.id)
          .toSet();
      final b = (await other.select(other.groceryItems).get())
          .map((r) => r.id)
          .toSet();
      expect(a, isNotEmpty);
      expect(a, b,
          reason: 'same plan → same derived ids → LWW converges instead of '
              'duplicating the onions');
    });

    test('regenerating after a plan change tombstones the gone items and '
        'keeps checked ones', () async {
      await seedPlanWithTacos(db);
      final repo = GroceryRepository(db);
      await repo.regenerateFromPlan(['2026-07-27']);

      final onion = (await db.select(db.groceryItems).get())
          .firstWhere((r) => r.name.contains('onion'));
      await repo.setChecked(onion.id, checked: true);

      // The plan empties; regen again.
      await PlanRepository(db).remove('p-1');
      await repo.regenerateFromPlan(['2026-07-27']);

      final rows = await db.select(db.groceryItems).get();
      final beef = rows.firstWhere((r) => r.name.contains('beef'));
      expect(beef.isDeleted, isTrue,
          reason: 'no longer in the plan and unchecked → tombstoned');
      final onionAfter = rows.firstWhere((r) => r.name.contains('onion'));
      expect(onionAfter.isDeleted, isFalse,
          reason: 'checked survivors are never swept by a regen');
      expect(onionAfter.checked, isTrue);
      expect((await repo.getAll()).map((g) => g.name),
          isNot(contains(contains('beef'))));
    });

    test('regen twice with the same plan is stable (no churn, no dupes)',
        () async {
      await seedPlanWithTacos(db);
      final repo = GroceryRepository(db);
      await repo.regenerateFromPlan(['2026-07-27']);
      final first = await db.select(db.groceryItems).get();
      await repo.regenerateFromPlan(['2026-07-27']);
      final second = await db.select(db.groceryItems).get();
      expect(second.length, first.length);
      expect(second.map((r) => r.id).toSet(),
          first.map((r) => r.id).toSet());
    });
  });
}
