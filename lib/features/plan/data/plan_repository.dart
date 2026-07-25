import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';

/// The week: upsert cells, read ranges with titles resolved live from the
/// recipe box / saved meals (a renamed recipe renames on the calendar).
class PlanRepository {
  PlanRepository(this._db);

  final AppDatabase _db;

  Future<void> upsert(PlanEntry entry) =>
      _db.into(_db.planEntries).insertOnConflictUpdate(PlanEntriesCompanion(
            id: Value(entry.id),
            day: Value(entry.day),
            slot: Value(PlanSlotDb.values[entry.slot.index]),
            kind: Value(PlanKindDb.values[entry.kind.index]),
            refId: Value(entry.refId),
            note: Value(entry.note),
          ));

  Future<void> remove(String id) =>
      (_db.delete(_db.planEntries)..where((p) => p.id.equals(id))).go();

  Future<List<PlanEntry>> entriesForDays(List<String> days) async {
    if (days.isEmpty) return const [];
    final rows = await (_db.select(_db.planEntries)
          ..where((p) => p.day.isIn(days))
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
    final recipeTitles = <String, String>{};
    if (recipeIds.isNotEmpty) {
      final recipes = await (_db.select(_db.recipes)
            ..where((r) => r.id.isIn(recipeIds)))
          .get();
      for (final r in recipes) {
        recipeTitles[r.id] = r.title;
      }
    }
    final mealNames = <String, String>{};
    if (mealIds.isNotEmpty) {
      final meals = await (_db.select(_db.savedMeals)
            ..where((m) => m.id.isIn(mealIds)))
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
