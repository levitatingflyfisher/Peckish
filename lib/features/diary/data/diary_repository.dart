import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// The food ledger: append entries, sum days by query, edit and delete
/// without ceremony. Totals are always computed from the stored snapshots —
/// never re-derived through today's food definitions.
class DiaryRepository {
  DiaryRepository(this._db);

  final AppDatabase _db;

  /// Every log also records the regular (count + newest snapshot) — one
  /// write path for all sources, so the rail can never miss a habit.
  Future<void> log(DiaryEntry entry) => _db.transaction(() async {
        await _db.into(_db.diaryEntries).insert(_toRow(entry));
        await FoodUsageRepository(_db).recordUsage(entry);
      });

  Future<void> update(DiaryEntry entry) =>
      _db.update(_db.diaryEntries).replace(_toRow(entry));

  Future<void> delete(String id) =>
      (_db.delete(_db.diaryEntries)..where((e) => e.id.equals(id))).go();

  Future<List<DiaryEntry>> entriesForDay(String day) async =>
      (await (_dayQuery(day)).get()).map(_toDomain).toList();

  Stream<List<DiaryEntry>> watchEntriesForDay(String day) =>
      _dayQuery(day).watch().map((rows) => rows.map(_toDomain).toList());

  Future<MacroSet> totalsForDay(String day) async =>
      _fold(await entriesForDay(day));

  Stream<MacroSet> watchTotalsForDay(String day) =>
      watchEntriesForDay(day).map(_fold);

  /// The one-tap rail: the persistent regulars, newest first, as template
  /// entries — relog by copying with a fresh id/day/at. Served from the
  /// FoodUsages record, NOT the ledger, so deleting a day's lines never
  /// empties the rail (the phone-test bug this replaced).
  Future<List<DiaryEntry>> recents({int limit = 12}) async =>
      (await FoodUsageRepository(_db).regulars(limit: limit))
          .map((u) => u.asTemplateEntry())
          .toList();

  SimpleSelectStatement<$DiaryEntriesTable, DiaryEntryRow> _dayQuery(
          String day) =>
      _db.select(_db.diaryEntries)
        ..where((e) => e.day.equals(day))
        ..orderBy([(e) => OrderingTerm.asc(e.at)]);

  /// Seeded with the all-null set, NOT [MacroSet.zero]: a day of kcal-only
  /// entries must report protein as unknown, never as a fake 0 g.
  static MacroSet _fold(List<DiaryEntry> entries) =>
      entries.fold(const MacroSet(), (sum, e) => sum + e.macros);

  static DiaryEntriesCompanion _toRow(DiaryEntry e) => DiaryEntriesCompanion(
        id: Value(e.id),
        day: Value(e.day),
        at: Value(e.at),
        foodKind: Value(FoodKindDb.values[e.food.kind.index]),
        usdaFdcId: Value(e.food.usdaFdcId),
        customFoodId: Value(e.food.customFoodId),
        label: Value(e.label),
        qty: Value(e.qty),
        unitLabel: Value(e.unitLabel),
        grams: Value(e.grams),
        kcal: Value(e.macros.kcal),
        proteinG: Value(e.macros.proteinG),
        carbG: Value(e.macros.carbG),
        fatG: Value(e.macros.fatG),
        source: Value(EntrySourceDb.values[e.source.index]),
        createdAt: Value(e.createdAt),
      );

  static DiaryEntry _toDomain(DiaryEntryRow r) => DiaryEntry(
        id: r.id,
        day: r.day,
        at: r.at,
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
        source: EntrySource.values[r.source.index],
        createdAt: r.createdAt,
      );
}
