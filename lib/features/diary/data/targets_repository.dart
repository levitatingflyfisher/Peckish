import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// Static personal targets, one row. Unset = all-null = the app shows plain
/// totals with no judgement. Deliberately no adaptive loop: the numbers
/// change when the user changes them (schema note: entry timestamps + these
/// static fields are all a future opt-in loop would need — nothing else is
/// pre-built). Roles ride along since v4; null roles resolve to axis
/// defaults in the domain, so pre-role rows keep working.
class TargetsRepository {
  TargetsRepository(this._db);

  final AppDatabase _db;

  Future<DailyTargets> get() async {
    final row = await (_db.select(_db.targets)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return _toDomain(row);
  }

  Stream<DailyTargets> watch() =>
      (_db.select(_db.targets)..where((t) => t.id.equals(1)))
          .watchSingleOrNull()
          .map(_toDomain);

  /// Full replace — clearing a slot (or a role) really clears it.
  Future<void> set(DailyTargets targets) =>
      _db.into(_db.targets).insertOnConflictUpdate(TargetsCompanion(
            id: const Value(1),
            kcal: Value(targets.values.kcal),
            proteinG: Value(targets.values.proteinG),
            carbG: Value(targets.values.carbG),
            fatG: Value(targets.values.fatG),
            kcalRole: Value(targets.kcalRole?.name),
            proteinRole: Value(targets.proteinRole?.name),
            carbRole: Value(targets.carbRole?.name),
            fatRole: Value(targets.fatRole?.name),
          ));

  static DailyTargets _toDomain(TargetsRow? row) => row == null
      ? const DailyTargets()
      : DailyTargets(
          values: MacroSet(
            kcal: row.kcal,
            proteinG: row.proteinG,
            carbG: row.carbG,
            fatG: row.fatG,
          ),
          kcalRole: TargetRole.tryParse(row.kcalRole),
          proteinRole: TargetRole.tryParse(row.proteinRole),
          carbRole: TargetRole.tryParse(row.carbRole),
          fatRole: TargetRole.tryParse(row.fatRole),
        );
}
