import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';

// The merge laws, tested on two REAL databases:
//  * per-row LWW — a strictly newer stamp wins, a stale one never clobbers,
//  * tombstones travel and are never resurrected by a stale peer,
//  * children (recipe ingredients) travel with their parent as one unit,
//  * a payload from a NEWER app version is refused before any write,
//  * the diary and targets never enter a changeset — the kitchen is
//    shared, the plate is yours.
void main() {
  late AppDatabase a;
  late AppDatabase b;

  setUp(() {
    a = AppDatabase(NativeDatabase.memory());
    b = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  CustomFood food(String id, String name) => CustomFood(
        id: id,
        name: name,
        servingLabel: '1 serving',
        perServing: const MacroSet(kcal: 100),
        createdAt: DateTime(2026),
      );

  test('a full exchange converges two fresh devices', () async {
    await CustomFoodRepository(a).create(food('cf-a', 'From A'));
    await CustomFoodRepository(b).create(food('cf-b', 'From B'));

    // Pull-then-push, like the client does.
    final fromA = await SyncEngine(a).buildChangeset();
    await SyncEngine(b).apply(fromA);
    final fromB = await SyncEngine(b).buildChangeset();
    await SyncEngine(a).apply(fromB);

    final namesA = (await CustomFoodRepository(a).getAll()).map((f) => f.name);
    final namesB = (await CustomFoodRepository(b).getAll()).map((f) => f.name);
    expect(namesA, containsAll(['From A', 'From B']));
    expect(namesB, containsAll(['From A', 'From B']));
  });

  test('LWW: the newer edit wins, the stale one never clobbers', () async {
    await CustomFoodRepository(a).create(food('cf-1', 'Original'));
    // B learns about it, then A renames (strictly later stamp).
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());
    await CustomFoodRepository(a).update(food('cf-1', 'Renamed on A'));

    // Stale B → A: must not clobber A's newer name.
    await SyncEngine(a).apply(await SyncEngine(b).buildChangeset());
    expect((await CustomFoodRepository(a).byId('cf-1'))!.name, 'Renamed on A');

    // Newer A → B: must apply.
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());
    expect((await CustomFoodRepository(b).byId('cf-1'))!.name, 'Renamed on A');
  });

  test('a tombstone travels, and a stale peer cannot resurrect it', () async {
    await CustomFoodRepository(a).create(food('cf-1', 'Doomed'));
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());
    expect(await CustomFoodRepository(b).byId('cf-1'), isNotNull);

    // A deletes (newer stamp); the deletion reaches B.
    await CustomFoodRepository(a).delete('cf-1');
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());
    expect(await CustomFoodRepository(b).byId('cf-1'), isNull,
        reason: 'the tombstone must travel');

    // B's stale live row must not resurrect the food on A.
    await SyncEngine(a).apply(await SyncEngine(b).buildChangeset());
    expect(await CustomFoodRepository(a).byId('cf-1'), isNull);
  });

  test('recipes travel with their ingredients as one unit', () async {
    await RecipeRepository(a).create(Recipe(
      id: 'r-1',
      title: 'Tacos',
      servings: 4,
      ingredients: const [
        RecipeIngredient(id: 'i-1', text: '1 onion'),
        RecipeIngredient(id: 'i-2', text: '500 g beef'),
      ],
      createdAt: DateTime(2026),
    ));
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());

    final onB = await RecipeRepository(b).byId('r-1');
    expect(onB, isNotNull);
    expect(onB!.ingredients.map((i) => i.text), ['1 onion', '500 g beef']);

    // An edit that changes the ingredient list replaces it wholesale on
    // the peer too.
    await RecipeRepository(a).update(Recipe(
      id: 'r-1',
      title: 'Tacos',
      servings: 4,
      ingredients: const [RecipeIngredient(id: 'i-3', text: '2 onions')],
      createdAt: DateTime(2026),
    ));
    await SyncEngine(b).apply(await SyncEngine(a).buildChangeset());
    expect(
        (await RecipeRepository(b).byId('r-1'))!.ingredients.map((i) => i.text),
        ['2 onions']);
  });

  test('the plate is yours: no diary, no targets in the payload', () async {
    await DiaryRepository(a).log(DiaryEntry(
      id: 'e-1',
      day: '2026-07-26',
      at: DateTime(2026, 7, 26, 12),
      food: const FoodRef.quick(),
      label: 'Private lunch',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: const MacroSet(kcal: 500),
      source: EntrySource.manual,
      createdAt: DateTime(2026, 7, 26, 12),
    ));

    final changeset = await SyncEngine(a).buildChangeset();
    final json = changeset.toJsonString();
    expect(json, isNot(contains('Private lunch')),
        reason: 'the label lands in diary AND food_usages — neither syncs');
    expect(json, isNot(contains('diary')));
    expect(json, isNot(contains('targets')));
    expect(json, isNot(contains('sage')),
        reason: "matches 'usage'/'foodUsages' — the regulars stay local");
  });

  test('a payload from a newer app version is refused before any write',
      () async {
    await CustomFoodRepository(a).create(food('cf-1', 'Original'));
    final changeset = await SyncEngine(b).buildChangeset();
    final future = SyncChangeset(
      senderNodeId: changeset.senderNodeId,
      senderHlc: changeset.senderHlc,
      data: const {
        'customFoods': [
          {'id': 'cf-1', 'name': 'From the future', 'hlc': '9999'},
        ],
      },
      payloadSchemaVersion: SyncChangeset.currentPayloadSchemaVersion + 1,
    );

    final result = await SyncEngine(a).apply(future);
    expect(result.isSuccess, isFalse);
    expect(result.error, contains('newer'));
    expect((await CustomFoodRepository(a).byId('cf-1'))!.name, 'Original',
        reason: 'nothing may be written before the version gate');
  });
}
