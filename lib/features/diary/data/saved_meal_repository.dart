import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// Staples: create a named bundle once, relog it forever in one tap.
/// Items are snapshots — deleting or editing a meal never touches diary
/// entries already logged from it. Household-shared: meal rows are
/// HLC-stamped, deletes tombstone the parent (items travel with it).
class SavedMealRepository {
  SavedMealRepository(this._db, {String Function()? idGenerator})
      : _newId = idGenerator ?? const Uuid().v4;

  final AppDatabase _db;
  final String Function() _newId;

  SyncClock get _clock => SyncClock.of(_db);

  Future<SavedMealsCompanion> _stamp(SavedMealsCompanion row) async {
    final s = await _clock.stamp();
    return row.copyWith(hlc: Value(s.hlc), nodeId: Value(s.nodeId));
  }

  Future<void> create(SavedMeal meal) async {
    final row = await _stamp(SavedMealsCompanion(
      id: Value(meal.id),
      name: Value(meal.name),
      position: Value(meal.position),
      createdAt: Value(meal.createdAt),
      lastUsedAt: Value(meal.lastUsedAt),
      archived: Value(meal.archived),
    ));
    await _db.transaction(() async {
        await _db.into(_db.savedMeals).insert(row);
        for (final (index, item) in meal.items.indexed) {
          await _db.into(_db.savedMealItems).insert(_itemRow(meal.id, index, item));
        }
      });
  }

  Future<void> rename(String id, String name) async =>
      (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(await _stamp(SavedMealsCompanion(name: Value(name))));

  /// Replace the item list wholesale — editing a staple is a re-declaration.
  /// Stamps the PARENT: items travel with their meal, so an item edit that
  /// left the parent stamp untouched would never reach the household.
  Future<void> replaceItems(String id, List<SavedMealItem> items) async {
    final stamp = await _stamp(const SavedMealsCompanion());
    await _db.transaction(() async {
      await (_db.delete(_db.savedMealItems)
            ..where((i) => i.mealId.equals(id)))
          .go();
      for (final (index, item) in items.indexed) {
        await _db.into(_db.savedMealItems).insert(_itemRow(id, index, item));
      }
      await (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(stamp);
    });
  }

  Future<void> reorder(List<String> idsInOrder) async {
    final stamps = <SavedMealsCompanion>[
      for (final _ in idsInOrder) const SavedMealsCompanion(),
    ];
    for (var i = 0; i < stamps.length; i++) {
      stamps[i] = await _stamp(stamps[i]);
    }
    await _db.transaction(() async {
      for (final (index, id) in idsInOrder.indexed) {
        await (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
            .write(stamps[index].copyWith(position: Value(index)));
      }
    });
  }

  Future<void> setArchived(String id, {required bool archived}) async =>
      (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(await _stamp(SavedMealsCompanion(archived: Value(archived))));

  Future<void> delete(String id) async {
    final row = await _stamp(
        const SavedMealsCompanion(isDeleted: Value(true)));
    await _db.transaction(() async {
      await (_db.delete(_db.savedMealItems)..where((i) => i.mealId.equals(id)))
          .go();
      await (_db.update(_db.savedMeals)..where((m) => m.id.equals(id)))
          .write(row);
    });
  }

  Future<List<SavedMeal>> getAll({bool includeArchived = false}) async {
    final mealQ = _db.select(_db.savedMeals)
      ..where((m) => m.isDeleted.equals(false))
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
  /// source = tap, and float the staple by stamping lastUsedAt. Goes through
  /// DiaryRepository.log — the single write path — so each item also records
  /// its regular.
  Future<void> logMeal(String id,
      {required DateTime at, required String day}) async {
    final meal =
        (await getAll(includeArchived: true)).firstWhere((m) => m.id == id);
    final diary = DiaryRepository(_db);
    await _db.transaction(() async {
      for (final item in meal.items) {
        await diary.log(DiaryEntry(
          id: _newId(),
          day: day,
          at: at,
          food: item.food,
          label: item.label,
          qty: item.qty,
          unitLabel: item.unitLabel,
          grams: item.grams,
          macros: item.macros,
          source: EntrySource.tap,
          createdAt: at,
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
