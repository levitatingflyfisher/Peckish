import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';

void main() {
  late AppDatabase db;
  late GroceryRepository repo;
  late PlanRepository plan;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = GroceryRepository(db, idGenerator: _counterIds());
    plan = PlanRepository(db);
    final recipes = RecipeRepository(db);
    await recipes.create(Recipe(
      id: 'r-tacos',
      title: 'Tacos',
      servings: 4,
      createdAt: DateTime(2026, 7, 25),
      ingredients: const [
        RecipeIngredient(id: 'i-1', text: '1 lb ground beef'),
        RecipeIngredient(id: 'i-2', text: '1 onion'),
        RecipeIngredient(id: 'i-3', text: '8 corn tortillas'),
      ],
    ));
    await recipes.create(Recipe(
      id: 'r-soup',
      title: 'Soup',
      servings: 6,
      createdAt: DateTime(2026, 7, 25),
      ingredients: const [
        RecipeIngredient(id: 'i-4', text: '1 onion'),
        RecipeIngredient(id: 'i-5', text: '2 cups milk'),
      ],
    ));
    await plan.upsert(const PlanEntry(
        id: 'p-1',
        day: '2026-07-27',
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-tacos'));
    await plan.upsert(const PlanEntry(
        id: 'p-2',
        day: '2026-07-28',
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-soup'));
  });

  tearDown(() => db.close());

  test('regenerate pulls every planned recipe line, aggregating duplicates',
      () async {
    await repo.regenerateFromPlan(['2026-07-27', '2026-07-28']);
    final items = await repo.getAll();
    final names = items.map((i) => i.name).toList();
    expect(names, contains('1 lb ground beef'));
    expect(names, contains('2 cups milk'));
    // "1 onion" appears in both recipes → one line, counted
    expect(names.where((n) => n.contains('onion')), hasLength(1));
    expect(names.singleWhere((n) => n.contains('onion')), '2× 1 onion');
  });

  test('lines are aisle-classified', () async {
    await repo.regenerateFromPlan(['2026-07-27', '2026-07-28']);
    final items = await repo.getAll();
    GroceryAisle aisleOf(String needle) =>
        items.firstWhere((i) => i.name.contains(needle)).aisle;
    expect(aisleOf('beef'), GroceryAisle.meat);
    expect(aisleOf('onion'), GroceryAisle.produce);
    expect(aisleOf('milk'), GroceryAisle.dairy);
    expect(aisleOf('tortillas'), GroceryAisle.bakery);
  });

  test('manual items survive regeneration', () async {
    await repo.addManual('Birthday candles');
    await repo.regenerateFromPlan(['2026-07-27']);
    final names = (await repo.getAll()).map((i) => i.name);
    expect(names, contains('Birthday candles'));
  });

  test('checked items survive regen and are not re-added as duplicates',
      () async {
    await repo.regenerateFromPlan(['2026-07-27']);
    final onion =
        (await repo.getAll()).firstWhere((i) => i.name.contains('onion'));
    await repo.setChecked(onion.id, checked: true);
    await repo.regenerateFromPlan(['2026-07-27']);
    final onions = (await repo.getAll())
        .where((i) => i.name.toLowerCase().contains('onion'));
    expect(onions, hasLength(1));
    expect(onions.single.checked, isTrue);
  });

  test('unchecked generated items are replaced on regen (plan changed)',
      () async {
    await repo.regenerateFromPlan(['2026-07-27', '2026-07-28']);
    expect((await repo.getAll()).map((i) => i.name), contains('2 cups milk'));
    // soup drops off the plan
    await plan.remove('p-2');
    await repo.regenerateFromPlan(['2026-07-27', '2026-07-28']);
    final names = (await repo.getAll()).map((i) => i.name).toList();
    expect(names, isNot(contains('2 cups milk')));
    expect(names.singleWhere((n) => n.contains('onion')), '1 onion');
  });

  test('check, uncheck, clearChecked', () async {
    await repo.addManual('Milk');
    await repo.addManual('Eggs');
    final items = await repo.getAll();
    await repo.setChecked(items.first.id, checked: true);
    await repo.clearChecked();
    final remaining = await repo.getAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.checked, isFalse);
  });
}

/// Deterministic ids for tests.
String Function() _counterIds() {
  var n = 0;
  return () => 'g-${n++}';
}
