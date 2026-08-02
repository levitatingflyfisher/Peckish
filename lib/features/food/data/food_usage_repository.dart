import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// The persistent regulars. Every diary log records a use (count + newest
/// snapshot); the rail and the Foods screen read from here, so a habit
/// survives any amount of diary editing. Local-only: derives from the diary,
/// and the plate is yours — never synced.
class FoodUsageRepository {
  FoodUsageRepository(this._db);

  final AppDatabase _db;

  /// Upsert one use. Out-of-order timestamps (a backup replay, an edited
  /// clock) bump the count but never roll the snapshot backwards; any fresh
  /// use unhides — reaching for a food again is a fresh signal.
  Future<void> recordUsage(DiaryEntry e) async {
    final key = e.food.identityKey(e.label);
    final existing = await (_db.select(_db.foodUsages)
          ..where((u) => u.identityKey.equals(key)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.foodUsages).insert(FoodUsagesCompanion.insert(
            identityKey: key,
            foodKind: FoodKindDb.values[e.food.kind.index],
            usdaFdcId: Value(e.food.usdaFdcId),
            customFoodId: Value(e.food.customFoodId),
            label: e.label,
            qty: e.qty,
            unitLabel: e.unitLabel,
            grams: Value(e.grams),
            kcal: Value(e.macros.kcal),
            proteinG: Value(e.macros.proteinG),
            carbG: Value(e.macros.carbG),
            fatG: Value(e.macros.fatG),
            useCount: 1,
            at: e.at,
          ));
      return;
    }
    final newer = !e.at.isBefore(existing.at);
    await (_db.update(_db.foodUsages)
          ..where((u) => u.identityKey.equals(key)))
        .write(FoodUsagesCompanion(
      useCount: Value(existing.useCount + 1),
      hidden: const Value(false),
      at: newer ? Value(e.at) : const Value.absent(),
      label: newer ? Value(e.label) : const Value.absent(),
      qty: newer ? Value(e.qty) : const Value.absent(),
      unitLabel: newer ? Value(e.unitLabel) : const Value.absent(),
      grams: newer ? Value(e.grams) : const Value.absent(),
      kcal: newer ? Value(e.macros.kcal) : const Value.absent(),
      proteinG: newer ? Value(e.macros.proteinG) : const Value.absent(),
      carbG: newer ? Value(e.macros.carbG) : const Value.absent(),
      fatG: newer ? Value(e.macros.fatG) : const Value.absent(),
    ));
  }

  /// The edit half of the single-write-path law: an updated entry re-shapes
  /// the snapshot IF it is (still) the newest use of that food — but an
  /// edit is not a fresh use, so the count never moves, `at` stays, and a
  /// hidden regular stays hidden.
  Future<void> refreshSnapshot(DiaryEntry e) async {
    final key = e.food.identityKey(e.label);
    final existing = await (_db.select(_db.foodUsages)
          ..where((u) => u.identityKey.equals(key)))
        .getSingleOrNull();
    if (existing == null || e.at.isBefore(existing.at)) return;
    await (_db.update(_db.foodUsages)
          ..where((u) => u.identityKey.equals(key)))
        .write(FoodUsagesCompanion(
      qty: Value(e.qty),
      unitLabel: Value(e.unitLabel),
      grams: Value(e.grams),
      kcal: Value(e.macros.kcal),
      proteinG: Value(e.macros.proteinG),
      carbG: Value(e.macros.carbG),
      fatG: Value(e.macros.fatG),
    ));
  }

  Future<List<FoodUsage>> regulars(
      {int limit = 12, bool includeHidden = false}) async {
    final q = _db.select(_db.foodUsages)
      ..orderBy([(u) => OrderingTerm.desc(u.at)])
      ..limit(limit);
    if (!includeHidden) q.where((u) => u.hidden.equals(false));
    return (await q.get()).map(_toDomain).toList();
  }

  Stream<List<FoodUsage>> watchAll() => (_db.select(_db.foodUsages)
        ..orderBy([(u) => OrderingTerm.desc(u.at)]))
      .watch()
      .map((rows) => rows.map(_toDomain).toList());

  /// The rail's live read: visible regulars, newest first, with the cap
  /// pushed into SQL — twelve chips should cost twelve rows per diary
  /// write, not a lifetime of habits re-read and re-mapped every log.
  Stream<List<FoodUsage>> watchVisible({int? limit}) {
    final q = _db.select(_db.foodUsages)
      ..where((u) => u.hidden.equals(false))
      ..orderBy([(u) => OrderingTerm.desc(u.at)]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// The suggestion engine's pool: visible regulars, most-used first with
  /// the engine's own label tie-break, capped in SQL at its ceiling.
  Stream<List<FoodUsage>> watchTopUsed({required int limit}) {
    final q = _db.select(_db.foodUsages)
      ..where((u) => u.hidden.equals(false))
      ..orderBy([
        (u) => OrderingTerm.desc(u.useCount),
        (u) => OrderingTerm.asc(u.label),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// Every regular, hidden included — the export/backup gathering path.
  Future<List<FoodUsage>> getAll() async =>
      (await (_db.select(_db.foodUsages)
                ..orderBy([(u) => OrderingTerm.desc(u.at)]))
              .get())
          .map(_toDomain)
          .toList();

  Future<void> setHidden(String identityKey, {required bool hidden}) =>
      (_db.update(_db.foodUsages)
            ..where((u) => u.identityKey.equals(identityKey)))
          .write(FoodUsagesCompanion(hidden: Value(hidden)));

  /// Restore path: re-seat an exported regular wholesale (counts + hidden
  /// flags are truth from the backup, not derivable from the replayed diary).
  Future<void> put(FoodUsage u) =>
      _db.into(_db.foodUsages).insert(
            FoodUsagesCompanion.insert(
              identityKey: u.identityKey,
              foodKind: FoodKindDb.values[u.food.kind.index],
              usdaFdcId: Value(u.food.usdaFdcId),
              customFoodId: Value(u.food.customFoodId),
              label: u.label,
              qty: u.qty,
              unitLabel: u.unitLabel,
              grams: Value(u.grams),
              kcal: Value(u.macros.kcal),
              proteinG: Value(u.macros.proteinG),
              carbG: Value(u.macros.carbG),
              fatG: Value(u.macros.fatG),
              useCount: u.useCount,
              at: u.lastUsedAt,
              hidden: Value(u.hidden),
            ),
            mode: InsertMode.insertOrReplace,
          );

  static FoodUsage _toDomain(FoodUsageRow r) => FoodUsage(
        identityKey: r.identityKey,
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
        useCount: r.useCount,
        lastUsedAt: r.at,
        hidden: r.hidden,
      );
}
