import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// The list that writes itself. Regeneration laws:
/// - manual items ALWAYS survive;
/// - checked items survive and are never re-added as duplicates (you already
///   bought the onions);
/// - unchecked generated items are replaced wholesale — they exist only as a
///   projection of the current plan.
///
/// Household-shared (the whole point: one list at the store — check off the
/// milk while your partner is in aisle 3). Writes are HLC-stamped, removals
/// tombstone, and derived rows get DETERMINISTIC ids from their normalized
/// line, so two devices regenerating the same plan converge on the same rows
/// instead of duplicating them.
class GroceryRepository {
  GroceryRepository(this._db, {String Function()? idGenerator})
      : _newId = idGenerator ?? const Uuid().v4;

  final AppDatabase _db;
  final String Function() _newId;

  SyncClock get _clock => SyncClock.of(_db);

  /// The convergence trick: same normalized ingredient line → same id on
  /// every device, forever.
  static String derivedId(String normalizedName) =>
      const Uuid().v5(Namespace.url.value, 'peckish:grocery:$normalizedName');

  Future<void> addManual(String name) async {
    final s = await _clock.stamp();
    await _db.into(_db.groceryItems).insert(GroceryItemsCompanion(
          id: Value(_newId()),
          name: Value(name),
          aisle: Value(GroceryAisleDb.values[classifyAisle(name).index]),
          checked: const Value(false),
          manual: const Value(true),
          createdAt: Value(DateTime.now()),
          hlc: Value(s.hlc),
          nodeId: Value(s.nodeId),
        ));
  }

  /// Re-insert a whole item verbatim (the backup-restore path): every field
  /// survives as exported, and the write is stamped like any other so the
  /// restored row can travel to peers instead of only ever filling holes.
  Future<void> upsert(GroceryItem item) async {
    final s = await _clock.stamp();
    await _db.into(_db.groceryItems).insertOnConflictUpdate(
          GroceryItemsCompanion(
            id: Value(item.id),
            name: Value(item.name),
            aisle: Value(GroceryAisleDb.values[item.aisle.index]),
            checked: Value(item.checked),
            manual: Value(item.manual),
            sourceRecipeId: Value(item.sourceRecipeId),
            createdAt: Value(item.createdAt),
            hlc: Value(s.hlc),
            nodeId: Value(s.nodeId),
            isDeleted: const Value(false),
          ),
        );
  }

  Future<void> setChecked(String id, {required bool checked}) async {
    final s = await _clock.stamp();
    await (_db.update(_db.groceryItems)..where((g) => g.id.equals(id)))
        .write(GroceryItemsCompanion(
      checked: Value(checked),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  Future<void> remove(String id) async {
    final s = await _clock.stamp();
    await (_db.update(_db.groceryItems)..where((g) => g.id.equals(id)))
        .write(GroceryItemsCompanion(
      isDeleted: const Value(true),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  /// Sweep the bought things off the list.
  Future<void> clearChecked() async {
    final s = await _clock.stamp();
    await (_db.update(_db.groceryItems)..where((g) => g.checked.equals(true)))
        .write(GroceryItemsCompanion(
      isDeleted: const Value(true),
      hlc: Value(s.hlc),
      nodeId: Value(s.nodeId),
    ));
  }

  Future<List<GroceryItem>> getAll() async {
    final rows = await (_db.select(_db.groceryItems)
          ..where((g) => g.isDeleted.equals(false))
          ..orderBy([
            (g) => OrderingTerm.asc(g.aisle),
            (g) => OrderingTerm.asc(g.name),
          ]))
        .get();
    return rows.map(_toDomain).toList();
  }

  Stream<List<GroceryItem>> watchAll() => (_db.select(_db.groceryItems))
      .watch()
      .asyncMap((_) => getAll());

  /// Rebuild the generated portion of the list from the recipes planned on
  /// [days]. Identical ingredient lines across recipes aggregate into one
  /// line with a count ("2× 1 onion"). Derived rows keep their deterministic
  /// id across regens (and across devices); rows that fall out of the plan
  /// tombstone instead of vanishing, so the disappearance syncs too.
  Future<void> regenerateFromPlan(List<String> days) async {
    final plan = await PlanRepository(_db).entriesForDays(days);
    final recipes = RecipeRepository(_db);

    // Collect ingredient lines from every planned recipe.
    final counts = <String, int>{}; // normalized → count
    final display = <String, String>{}; // normalized → original line
    final source = <String, String>{}; // normalized → recipeId
    for (final entry in plan.where((e) => e.kind == PlanKind.recipe)) {
      final recipe =
          entry.refId == null ? null : await recipes.byId(entry.refId!);
      if (recipe == null) continue;
      for (final line in recipe.ingredients) {
        final norm = _normalize(line.text);
        if (norm.isEmpty) continue;
        counts[norm] = (counts[norm] ?? 0) + 1;
        display.putIfAbsent(norm, () => line.text.trim());
        source.putIfAbsent(norm, () => recipe.id);
      }
    }

    final s = await _clock.stamp();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.groceryItems)).get();

      // Live survivors suppress duplicates by normalized name (the "you
      // already bought the onions" law). _normalize strips a leading "N× ",
      // so a checked "2× 1 onion" suppresses "1 onion" too.
      final liveCheckedNorms = {
        for (final r in existing)
          if (!r.isDeleted && r.checked) _normalize(r.name),
      };
      final liveManualNorms = {
        for (final r in existing)
          if (!r.isDeleted && r.manual) _normalize(r.name),
      };

      final wantedIds = <String>{};
      for (final entry in counts.entries) {
        final norm = entry.key;
        final id = derivedId(norm);
        wantedIds.add(id);
        if (liveCheckedNorms.contains(norm) ||
            liveManualNorms.contains(norm)) {
          continue;
        }
        final name = entry.value > 1
            ? '${entry.value}× ${display[norm]}'
            : display[norm]!;
        await _db.into(_db.groceryItems).insertOnConflictUpdate(
              GroceryItemsCompanion(
                id: Value(id),
                name: Value(name),
                aisle: Value(
                    GroceryAisleDb.values[classifyAisle(display[norm]!).index]),
                checked: const Value(false),
                manual: const Value(false),
                sourceRecipeId: Value(source[norm]),
                createdAt: Value(DateTime.now()),
                hlc: Value(s.hlc),
                nodeId: Value(s.nodeId),
                isDeleted: const Value(false),
              ),
            );
      }

      // Derived + unchecked + no longer wanted → tombstone (the projection
      // shrank, and the shrink has to travel).
      for (final r in existing) {
        if (!r.manual &&
            !r.checked &&
            !r.isDeleted &&
            !wantedIds.contains(r.id)) {
          await (_db.update(_db.groceryItems)..where((g) => g.id.equals(r.id)))
              .write(GroceryItemsCompanion(
            isDeleted: const Value(true),
            hlc: Value(s.hlc),
            nodeId: Value(s.nodeId),
          ));
        }
      }
    });
  }

  /// Normalization for dedupe: lowercase, collapse whitespace, strip a
  /// leading "N× " count so regenerated lines match checked survivors.
  static String _normalize(String s) => s
      .toLowerCase()
      .replaceFirst(RegExp(r'^\d+×\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static GroceryItem _toDomain(GroceryItemRow r) => GroceryItem(
        id: r.id,
        name: r.name,
        aisle: GroceryAisle.values[r.aisle.index],
        checked: r.checked,
        manual: r.manual,
        sourceRecipeId: r.sourceRecipeId,
        createdAt: r.createdAt,
      );
}
