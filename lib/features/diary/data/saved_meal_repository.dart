import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// Staples: create a named bundle once, relog it forever in one tap.
/// Items are snapshots — deleting or editing a meal never touches diary
/// entries already logged from it.
class SavedMealRepository {
  SavedMealRepository(this._db, {String Function()? idGenerator})
      : _newId = idGenerator ?? const Uuid().v4;

  final AppDatabase _db;
  final String Function() _newId;

  Future<void> create(SavedMeal meal) => _db.transaction(() async {
        await _db.into(_db.savedMeals).insert(SavedMealsCompanion(
              id: Value(meal.id),
              name: Value(meal.name),
              position: Value(meal.position),
              createdAt: Value(meal.createdAt),
              lastUsedAt: Value(meal.lastUsedAt),
              archived: Value(meal.archived),
            ));
        for (final (index, item) in meal.items.indexed) {
          await _db.into(_db.savedMealItems).insert(_itemRow(meal.id, index, item));
        }
      });

  Future<void> rename(String id, String name) =>
      (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(SavedMealsCompanion(name: Value(name)));

  /// Replace the item list wholesale — editing a staple is a re-declaration.
  Future<void> replaceItems(String id, List<SavedMealItem> items) =>
      _db.transaction(() async {
        await (_db.delete(_db.savedMealItems)
              ..where((i) => i.mealId.equals(id)))
            .go();
        for (final (index, item) in items.indexed) {
          await _db.into(_db.savedMealItems).insert(_itemRow(id, index, item));
        }
      });

  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
        for (final (index, id) in idsInOrder.indexed) {
          await (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
              .write(SavedMealsCompanion(position: Value(index)));
        }
      });

  Future<void> setArchived(String id, {required bool archived}) =>
      (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(SavedMealsCompanion(archived: Value(archived)));

  Future<void> delete(String id) => _db.transaction(() async {
        await (_db.delete(_db.savedMealItems)..where((i) => i.mealId.equals(id)))
            .go();
        await (_db.delete(_db.savedMeals)..where((m) => m.id.equals(id))).go();
      });

  Future<List<SavedMeal>> getAll({bool includeArchived = false}) async {
    final mealQ = _db.select(_db.savedMeals)
      ..orderBy([(m) => OrderingTerm.asc(m.position)]);
    if (!includeArchived) mealQ.where((m) => m.archived.equals(false));
    final meals = await mealQ.get();
    final items = await (_db.select(_db.savedMealItems)
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .get();
    final byMeal = <String, List<SavedMealItem>>{};
    for (final i in items) {
      byMeal.putIfAbsent(i.mealId, () => []).add(_itemDomain(i));
    }
    return [
      for (final m in meals)
        SavedMeal(
          id: m.id,
          name: m.name,
          position: m.position,
          createdAt: m.createdAt,
          lastUsedAt: m.lastUsedAt,
          archived: m.archived,
          items: byMeal[m.id] ?? const [],
        ),
    ];
  }

  Stream<List<SavedMeal>> watchAll() {
    // Watch both tables; re-read on either changing.
    final mealsStream = (_db.select(_db.savedMeals)).watch();
    return mealsStream.asyncMap((_) => getAll());
  }

  /// THE one-tap: copy every item into today's ledger, stamped [at]/[day],
  /// source = tap, and float the staple by stamping lastUsedAt.
  Future<void> logMeal(String id,
      {required DateTime at, required String day}) async {
    final meal =
        (await getAll(includeArchived: true)).firstWhere((m) => m.id == id);
    await _db.transaction(() async {
      for (final item in meal.items) {
        await _db.into(_db.diaryEntries).insert(DiaryEntriesCompanion(
              id: Value(_newId()),
              day: Value(day),
              at: Value(at),
              foodKind: Value(FoodKindDb.values[item.food.kind.index]),
              usdaFdcId: Value(item.food.usdaFdcId),
              customFoodId: Value(item.food.customFoodId),
              label: Value(item.label),
              qty: Value(item.qty),
              unitLabel: Value(item.unitLabel),
              grams: Value(item.grams),
              kcal: Value(item.macros.kcal),
              proteinG: Value(item.macros.proteinG),
              carbG: Value(item.macros.carbG),
              fatG: Value(item.macros.fatG),
              source: const Value(EntrySourceDb.tap),
              createdAt: Value(at),
            ));
      }
      await (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(SavedMealsCompanion(lastUsedAt: Value(at)));
    });
  }

  static SavedMealItemsCompanion _itemRow(
          String mealId, int position, SavedMealItem item) =>
      SavedMealItemsCompanion(
        id: Value(item.id),
        mealId: Value(mealId),
        position: Value(position),
        foodKind: Value(FoodKindDb.values[item.food.kind.index]),
        usdaFdcId: Value(item.food.usdaFdcId),
        customFoodId: Value(item.food.customFoodId),
        label: Value(item.label),
        qty: Value(item.qty),
        unitLabel: Value(item.unitLabel),
        grams: Value(item.grams),
        kcal: Value(item.macros.kcal),
        proteinG: Value(item.macros.proteinG),
        carbG: Value(item.macros.carbG),
        fatG: Value(item.macros.fatG),
      );

  static SavedMealItem _itemDomain(SavedMealItemRow r) => SavedMealItem(
        id: r.id,
        food: switch (r.foodKind) {
          FoodKindDb.usda => FoodRef.usda(r.usdaFdcId!),
          FoodKindDb.custom => FoodRef.custom(r.customFoodId!),
          FoodKindDb.quick => const FoodRef.quick(),
        },
        label: r.label,
        qty: r.qty,
        unitLabel: r.unitLabel,
        grams: r.grams,
        macros: MacroSet(
          kcal: r.kcal,
          proteinG: r.proteinG,
          carbG: r.carbG,
          fatG: r.fatG,
        ),
      );
}
