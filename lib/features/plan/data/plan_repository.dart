import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// The week: upsert cells, read ranges with titles resolved live from the
/// recipe box / saved meals (a renamed recipe renames on the calendar).
/// Household-shared: writes are HLC-stamped, removals tombstone.
class PlanRepository {
  PlanRepository(this._db);

  final AppDatabase _db;

  SyncClock get _clock => SyncClock.of(_db);

  Future<void> upsert(PlanEntry entry) async {
    final s = await _clock.stamp();
    await _db
        .into(_db.planEntries)
        .insertOnConflictUpdate(PlanEntriesCompanion(
          id: Value(entry.id),
          day: Value(entry.day),
          slot: Value(PlanSlotDb.values[entry.slot.index]),
          kind: Value(PlanKindDb.values[entry.kind.index]),
          refId: Value(entry.refId),
          note: Value(entry.note),
          hlc: Value(s.hlc),
          nodeId: Value(s.nodeId),
          isDeleted: const Value(false),
        ));
  }

  Future<void> remove(String id) async {
    final s = await _clock.stamp();
    await (_db.update(_db.planEntries)..where((p) => p.id.equals(id)))
        .write(PlanEntriesCompanion(
      isDeleted: const Value(true),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  /// Every live cell, for the export/backup snapshot. Mirrors
  /// `GroceryRepository.getAll`: the tombstone filter lives HERE, so a
  /// backup can never carry a deletion out as a live row. Titles stay
  /// unresolved — they are read-side display only and the export omits them.
  Future<List<PlanEntry>> getAll() async {
    final rows = await (_db.select(_db.planEntries)
          ..where((p) => p.isDeleted.equals(false))
          ..orderBy([
            (p) => OrderingTerm.asc(p.day),
            (p) => OrderingTerm.asc(p.slot),
          ]))
        .get();
    return [
      for (final r in rows)
        PlanEntry(
          id: r.id,
          day: r.day,
          slot: PlanSlot.values[r.slot.index],
          kind: PlanKind.values[r.kind.index],
          refId: r.refId,
          note: r.note,
        ),
    ];
  }

  Future<List<PlanEntry>> entriesForDays(List<String> days) async {
    if (days.isEmpty) return const [];
    final rows = await (_db.select(_db.planEntries)
          ..where((p) => p.day.isIn(days) & p.isDeleted.equals(false))
          ..orderBy([
            (p) => OrderingTerm.asc(p.day),
            (p) => OrderingTerm.asc(p.slot),
          ]))
        .get();
    return _resolveTitles(rows);
  }

  Stream<List<PlanEntry>> watchDays(List<String> days) =>
      (_db.select(_db.planEntries)..where((p) => p.day.isIn(days)))
          .watch()
          .asyncMap((_) => entriesForDays(days));

  Future<List<PlanEntry>> _resolveTitles(List<PlanEntryRow> rows) async {
    final recipeIds = <String>{
      for (final r in rows)
        if (r.kind == PlanKindDb.recipe && r.refId != null) r.refId!,
    };
    final mealIds = <String>{
      for (final r in rows)
        if (r.kind == PlanKindDb.meal && r.refId != null) r.refId!,
    };
    // Tombstoned refs resolve like hard-deleted ones: '(deleted …)'.
    final recipeTitles = <String, String>{};
    if (recipeIds.isNotEmpty) {
      final recipes = await (_db.select(_db.recipes)
            ..where((r) => r.id.isIn(recipeIds) & r.isDeleted.equals(false)))
          .get();
      for (final r in recipes) {
        recipeTitles[r.id] = r.title;
      }
    }
    final mealNames = <String, String>{};
    if (mealIds.isNotEmpty) {
      final meals = await (_db.select(_db.savedMeals)
            ..where((m) => m.id.isIn(mealIds) & m.isDeleted.equals(false)))
          .get();
      for (final m in meals) {
        mealNames[m.id] = m.name;
      }
    }
    return [
      for (final r in rows)
        PlanEntry(
          id: r.id,
          day: r.day,
          slot: PlanSlot.values[r.slot.index],
          kind: PlanKind.values[r.kind.index],
          refId: r.refId,
          note: r.note,
          title: switch (r.kind) {
            PlanKindDb.recipe =>
              recipeTitles[r.refId] ?? '(deleted recipe)',
            PlanKindDb.meal => mealNames[r.refId] ?? '(deleted meal)',
            PlanKindDb.note => r.note ?? '',
          },
        ),
    ];
  }
}
