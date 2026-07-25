import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';

/// The list that writes itself. Regeneration laws:
/// - manual items ALWAYS survive;
/// - checked items survive and are never re-added as duplicates (you already
///   bought the onions);
/// - unchecked generated items are replaced wholesale — they exist only as a
///   projection of the current plan.
class GroceryRepository {
  GroceryRepository(this._db, {String Function()? idGenerator})
      : _newId = idGenerator ?? const Uuid().v4;

  final AppDatabase _db;
  final String Function() _newId;

  Future<void> addManual(String name) =>
      _db.into(_db.groceryItems).insert(GroceryItemsCompanion(
            id: Value(_newId()),
            name: Value(name),
            aisle: Value(GroceryAisleDb.values[classifyAisle(name).index]),
            checked: const Value(false),
            manual: const Value(true),
            createdAt: Value(DateTime.now()),
          ));

  Future<void> setChecked(String id, {required bool checked}) =>
      (_db.update(_db.groceryItems)..where((g) => g.id.equals(id)))
          .write(GroceryItemsCompanion(checked: Value(checked)));

  Future<void> remove(String id) =>
      (_db.delete(_db.groceryItems)..where((g) => g.id.equals(id))).go();

  /// Sweep the bought things off the list.
  Future<void> clearChecked() =>
      (_db.delete(_db.groceryItems)..where((g) => g.checked.equals(true))).go();

  Future<List<GroceryItem>> getAll() async {
    final rows = await (_db.select(_db.groceryItems)
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
  /// line with a count ("2× 1 onion").
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

    await _db.transaction(() async {
      // Replace only the unchecked generated projection.
      await (_db.delete(_db.groceryItems)
            ..where((g) => g.manual.equals(false) & g.checked.equals(false)))
          .go();

      // Survivors (manual or checked) suppress duplicates by normalized name.
      final survivors = await (_db.select(_db.groceryItems)).get();
      final surviving = {for (final s in survivors) _normalize(s.name)};

      for (final entry in counts.entries) {
        // A checked "2× 1 onion" survivor must also suppress "1 onion".
        if (surviving.contains(entry.key) ||
            surviving.any((s) => s.endsWith('× ${entry.key}'))) {
          continue;
        }
        final name = entry.value > 1
            ? '${entry.value}× ${display[entry.key]}'
            : display[entry.key]!;
        await _db.into(_db.groceryItems).insert(GroceryItemsCompanion(
              id: Value(_newId()),
              name: Value(name),
              aisle: Value(
                  GroceryAisleDb.values[classifyAisle(display[entry.key]!).index]),
              checked: const Value(false),
              manual: const Value(false),
              sourceRecipeId: Value(source[entry.key]),
              createdAt: Value(DateTime.now()),
            ));
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
