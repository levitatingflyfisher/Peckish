import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// The recipe box — full CRUD; ingredient lists replace wholesale on update
/// (editing a recipe is a re-declaration, not a diff). Household-shared:
/// recipe rows are HLC-stamped and deletes tombstone the parent (ingredients
/// travel with their recipe, so a tombstoned recipe's lines are dropped —
/// only the tombstone itself needs to survive).
class RecipeRepository {
  RecipeRepository(this._db);

  final AppDatabase _db;

  SyncClock get _clock => SyncClock.of(_db);

  Future<void> create(Recipe recipe) async {
    final row = await _stamped(_recipeRow(recipe));
    await _db.transaction(() async {
      await _db.into(_db.recipes).insert(row);
      await _insertIngredients(recipe.id, recipe.ingredients);
    });
  }

  Future<void> update(Recipe recipe) async {
    final row = await _stamped(_recipeRow(recipe));
    await _db.transaction(() async {
      await _db.update(_db.recipes).replace(row);
      await (_db.delete(_db.recipeIngredients)
            ..where((i) => i.recipeId.equals(recipe.id)))
          .go();
      await _insertIngredients(recipe.id, recipe.ingredients);
    });
  }

  Future<void> setArchived(String id, {required bool archived}) async {
    final s = await _clock.stamp();
    await (_db.update(_db.recipes)..where((r) => r.id.equals(id)))
        .write(RecipesCompanion(
      archived: Value(archived),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  Future<void> delete(String id) async {
    final s = await _clock.stamp();
    await _db.transaction(() async {
      await (_db.delete(_db.recipeIngredients)
            ..where((i) => i.recipeId.equals(id)))
          .go();
      await (_db.update(_db.recipes)..where((r) => r.id.equals(id)))
          .write(RecipesCompanion(
        isDeleted: const Value(true),
        hlc: Value(s.hlc),
        nodeId: Value(s.nodeId),
      ));
    });
  }

  Future<RecipesCompanion> _stamped(RecipesCompanion row) async {
    final s = await _clock.stamp();
    return row.copyWith(hlc: Value(s.hlc), nodeId: Value(s.nodeId));
  }

  Future<Recipe?> byId(String id) async {
    final row = await (_db.select(_db.recipes)
          ..where((r) => r.id.equals(id) & r.isDeleted.equals(false)))
        .getSingleOrNull();
    if (row == null) return null;
    final items = await (_db.select(_db.recipeIngredients)
          ..where((i) => i.recipeId.equals(id))
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .get();
    return _toDomain(row, items);
  }

  Future<List<Recipe>> getAll({bool includeArchived = false}) async {
    final q = _db.select(_db.recipes)
      ..where((r) => r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.asc(r.title)]);
    if (!includeArchived) q.where((r) => r.archived.equals(false));
    final rows = await q.get();
    final items = await (_db.select(_db.recipeIngredients)
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .get();
    final byRecipe = <String, List<RecipeIngredientRow>>{};
    for (final i in items) {
      byRecipe.putIfAbsent(i.recipeId, () => []).add(i);
    }
    return [
      for (final r in rows) _toDomain(r, byRecipe[r.id] ?? const []),
    ];
  }

  Stream<List<Recipe>> watchAll() =>
      (_db.select(_db.recipes)).watch().asyncMap((_) => getAll());

  Future<void> _insertIngredients(
      String recipeId, List<RecipeIngredient> items) async {
    for (final (index, item) in items.indexed) {
      await _db.into(_db.recipeIngredients).insert(RecipeIngredientsCompanion(
            id: Value(item.id),
            recipeId: Value(recipeId),
            position: Value(index),
            line: Value(item.text),
            foodKind: Value(item.food == null
                ? null
                : FoodKindDb.values[item.food!.kind.index]),
            usdaFdcId: Value(item.food?.usdaFdcId),
            customFoodId: Value(item.food?.customFoodId),
            grams: Value(item.grams),
            kcal: Value(item.macros?.kcal),
            proteinG: Value(item.macros?.proteinG),
            carbG: Value(item.macros?.carbG),
            fatG: Value(item.macros?.fatG),
          ));
    }
  }

  static RecipesCompanion _recipeRow(Recipe r) => RecipesCompanion(
        id: Value(r.id),
        title: Value(r.title),
        servings: Value(r.servings),
        sourceUrl: Value(r.sourceUrl),
        instructions: Value(r.instructions),
        declaredKcal: Value(r.declaredPerServing?.kcal),
        declaredProteinG: Value(r.declaredPerServing?.proteinG),
        declaredCarbG: Value(r.declaredPerServing?.carbG),
        declaredFatG: Value(r.declaredPerServing?.fatG),
        createdAt: Value(r.createdAt),
        archived: Value(r.archived),
      );

  static Recipe _toDomain(RecipeRow r, List<RecipeIngredientRow> items) {
    final declared = MacroSet(
      kcal: r.declaredKcal,
      proteinG: r.declaredProteinG,
      carbG: r.declaredCarbG,
      fatG: r.declaredFatG,
    );
    final declaredEmpty = declared.kcal == null &&
        declared.proteinG == null &&
        declared.carbG == null &&
        declared.fatG == null;
    return Recipe(
      id: r.id,
      title: r.title,
      servings: r.servings,
      sourceUrl: r.sourceUrl,
      instructions: r.instructions,
      declaredPerServing: declaredEmpty ? null : declared,
      createdAt: r.createdAt,
      archived: r.archived,
      ingredients: [
        for (final i in items)
          RecipeIngredient(
            id: i.id,
            text: i.line,
            food: switch (i.foodKind) {
              null => null,
              FoodKindDb.usda => FoodRef.usda(i.usdaFdcId!),
              FoodKindDb.custom => FoodRef.custom(i.customFoodId!),
              FoodKindDb.quick => const FoodRef.quick(),
            },
            grams: i.grams,
            macros: (i.kcal == null &&
                    i.proteinG == null &&
                    i.carbG == null &&
                    i.fatG == null)
                ? null
                : MacroSet(
                    kcal: i.kcal,
                    proteinG: i.proteinG,
                    carbG: i.carbG,
                    fatG: i.fatG,
                  ),
          ),
      ],
    );
  }
}
