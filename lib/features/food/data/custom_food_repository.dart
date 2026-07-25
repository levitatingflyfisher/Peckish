import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// Household custom foods — full CRUD, no ceremony. Archive hides a food from
/// pickers without touching history; delete removes the row (past diary
/// entries carry their own snapshots and are unaffected either way).
class CustomFoodRepository {
  CustomFoodRepository(this._db);

  final AppDatabase _db;

  Future<void> create(CustomFood food) =>
      _db.into(_db.customFoods).insert(_toRow(food));

  Future<void> update(CustomFood food) =>
      _db.update(_db.customFoods).replace(_toRow(food));

  Future<void> setArchived(String id, {required bool archived}) =>
      (_db.update(_db.customFoods)..where((f) => f.id.equals(id)))
          .write(CustomFoodsCompanion(archived: Value(archived)));

  Future<void> delete(String id) =>
      (_db.delete(_db.customFoods)..where((f) => f.id.equals(id))).go();

  Future<CustomFood?> byId(String id) async {
    final row = await (_db.select(_db.customFoods)
          ..where((f) => f.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<List<CustomFood>> getAll({bool includeArchived = false}) async {
    final q = _db.select(_db.customFoods)
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);
    if (!includeArchived) q.where((f) => f.archived.equals(false));
    return (await q.get()).map(_toDomain).toList();
  }

  Stream<List<CustomFood>> watchAll() => (_db.select(_db.customFoods)
        ..where((f) => f.archived.equals(false))
        ..orderBy([(f) => OrderingTerm.asc(f.name)]))
      .watch()
      .map((rows) => rows.map(_toDomain).toList());

  static CustomFoodsCompanion _toRow(CustomFood f) => CustomFoodsCompanion(
        id: Value(f.id),
        name: Value(f.name),
        servingLabel: Value(f.servingLabel),
        kcal: Value(f.perServing.kcal),
        proteinG: Value(f.perServing.proteinG),
        carbG: Value(f.perServing.carbG),
        fatG: Value(f.perServing.fatG),
        createdAt: Value(f.createdAt),
        archived: Value(f.archived),
      );

  static CustomFood _toDomain(CustomFoodRow r) => CustomFood(
        id: r.id,
        name: r.name,
        servingLabel: r.servingLabel,
        perServing: MacroSet(
          kcal: r.kcal,
          proteinG: r.proteinG,
          carbG: r.carbG,
          fatG: r.fatG,
        ),
        createdAt: r.createdAt,
        archived: r.archived,
      );
}
