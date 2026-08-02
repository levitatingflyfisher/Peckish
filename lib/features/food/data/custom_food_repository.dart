import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/domain/barcode_normalize.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// Household custom foods — full CRUD, no ceremony. Archive hides a food from
/// pickers without touching history; delete tombstones the row (so the
/// deletion can travel to household peers; past diary entries carry their own
/// snapshots and are unaffected either way). Every write is HLC-stamped —
/// this table is household-shared.
class CustomFoodRepository {
  CustomFoodRepository(this._db);

  final AppDatabase _db;

  SyncClock get _clock => SyncClock.of(_db);

  Future<void> create(CustomFood food) async =>
      _db.into(_db.customFoods).insert(await _stamped(_toRow(food)));

  Future<void> update(CustomFood food) async =>
      _db.update(_db.customFoods).replace(await _stamped(_toRow(food)));

  Future<void> setArchived(String id, {required bool archived}) async {
    final s = await _clock.stamp();
    await (_db.update(_db.customFoods)..where((f) => f.id.equals(id)))
        .write(CustomFoodsCompanion(
      archived: Value(archived),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  /// Tombstone, not removal — the delete has to be able to travel.
  Future<void> delete(String id) async {
    final s = await _clock.stamp();
    await (_db.update(_db.customFoods)..where((f) => f.id.equals(id)))
        .write(CustomFoodsCompanion(
      isDeleted: const Value(true),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  /// The household's own answer to a scanned code. Matched on the
  /// normalized form, so a UPC-A saved off a tin answers the EAN-13 the
  /// camera reads. Resting foods still answer: archiving hides a food from
  /// the pickers, and holding its barcode up is not picking from a list.
  Future<CustomFood?> byBarcode(String barcode) async {
    final key = normalizeBarcode(barcode);
    final row = await (_db.select(_db.customFoods)
          ..where((f) => f.barcode.equals(key) & f.isDeleted.equals(false))
          ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<CustomFood?> byId(String id) async {
    final row = await (_db.select(_db.customFoods)
          ..where((f) => f.id.equals(id) & f.isDeleted.equals(false)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<List<CustomFood>> getAll({bool includeArchived = false}) async {
    final q = _db.select(_db.customFoods)
      ..where((f) => f.isDeleted.equals(false))
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);
    if (!includeArchived) q.where((f) => f.archived.equals(false));
    return (await q.get()).map(_toDomain).toList();
  }

  Stream<List<CustomFood>> watchAll() => (_db.select(_db.customFoods)
        ..where((f) => f.archived.equals(false) & f.isDeleted.equals(false))
        ..orderBy([(f) => OrderingTerm.asc(f.name)]))
      .watch()
      .map((rows) => rows.map(_toDomain).toList());

  Future<CustomFoodsCompanion> _stamped(CustomFoodsCompanion row) async {
    final s = await _clock.stamp();
    return row.copyWith(hlc: Value(s.hlc), nodeId: Value(s.nodeId));
  }

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
        // Normalized on the way IN, so every read is a plain equality.
        barcode: Value(
            f.barcode == null ? null : normalizeBarcode(f.barcode!)),
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
        barcode: r.barcode,
      );
}
