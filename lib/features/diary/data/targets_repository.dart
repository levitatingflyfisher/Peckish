import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// Static personal targets, one row. Unset = all-null = the app shows plain
/// totals with no judgement. Deliberately no adaptive loop: the numbers
/// change when the user changes them (schema note: entry timestamps + these
/// static fields are all a future opt-in loop would need — nothing else is
/// pre-built).
class TargetsRepository {
  TargetsRepository(this._db);

  final AppDatabase _db;

  Future<MacroSet> get() async {
    final row = await (_db.select(_db.targets)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (row == null) return const MacroSet();
    return MacroSet(
      kcal: row.kcal,
      proteinG: row.proteinG,
      carbG: row.carbG,
      fatG: row.fatG,
    );
  }

  Stream<MacroSet> watch() =>
      (_db.select(_db.targets)..where((t) => t.id.equals(1)))
          .watchSingleOrNull()
          .map((row) => row == null
              ? const MacroSet()
              : MacroSet(
                  kcal: row.kcal,
                  proteinG: row.proteinG,
                  carbG: row.carbG,
                  fatG: row.fatG,
                ));

  /// Full replace — clearing a slot really clears it.
  Future<void> set(MacroSet targets) =>
      _db.into(_db.targets).insertOnConflictUpdate(TargetsCompanion(
            id: const Value(1),
            kcal: Value(targets.kcal),
            proteinG: Value(targets.proteinG),
            carbG: Value(targets.carbG),
            fatG: Value(targets.fatG),
          ));
}
