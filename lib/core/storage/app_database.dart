// lib/core/storage/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ─── Tables ───────────────────────────────────────────────────────────────────

/// Simple key→value store for shell preferences (theme, etc.).
class UserPrefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The bundled USDA reference spine (see assets/food/ + tool/usda/).
/// Reference data, not user data: survives [AppDatabase.eraseUserData] and is
/// wholesale-replaced when the shipped spine version changes. All macro
/// values are per 100 g.
@DataClassName('UsdaFoodRow')
class UsdaFoods extends Table {
  IntColumn get fdcId => integer()();
  TextColumn get source => text()();
  TextColumn get name => text()();

  /// Lowercased [name], the search column (LIKE scans stay index-friendly on
  /// one normalized spelling).
  TextColumn get nameNorm => text()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();

  @override
  Set<Column> get primaryKey => {fdcId};
}

/// Household portions for USDA foods ("1 medium (3\" dia)" → 182 g).
@DataClassName('UsdaPortionRow')
class UsdaPortions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fdcId => integer()();
  TextColumn get label => text()();
  RealColumn get grams => real()();
}

/// The sync metadata every household-SHARED table carries (v0.2, schema v2):
/// per-row HLC + writer node for last-write-wins merging, and a tombstone
/// instead of hard deletes so a deletion travels. Null hlc/nodeId = written
/// before sync existed (or with sync off); enabling sync backfills stamps.
/// Diary entries and targets are deliberately NOT in this club — the
/// kitchen is shared, the plate is yours.
mixin SyncColumns on Table {
  TextColumn get hlc => text().nullable()();
  TextColumn get nodeId => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

/// Household-defined foods. Macros are PER SERVING.
@DataClassName('CustomFoodRow')
class CustomFoods extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get servingLabel => text()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The food ledger. Macros are a snapshot taken at log time; `day` is a local
/// 'YYYY-MM-DD' string so DST can never move an entry across midnight.
@DataClassName('DiaryEntryRow')
class DiaryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get day => text()();
  DateTimeColumn get at => dateTime()();
  IntColumn get foodKind => intEnum<FoodKindDb>()();
  IntColumn get usdaFdcId => integer().nullable()();
  TextColumn get customFoodId => text().nullable()();
  TextColumn get label => text()();
  RealColumn get qty => real()();
  TextColumn get unitLabel => text()();
  RealColumn get grams => real().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  IntColumn get source => intEnum<EntrySourceDb>()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Storage-side enums for [DiaryEntries]. Kept separate from the domain enums
/// so a domain reorder can never silently rewrite what stored integers mean.
enum FoodKindDb { usda, custom, quick }

enum EntrySourceDb { tap, search, manual, ai, scan }

/// Staples — named bundles relogged in one tap.
@DataClassName('SavedMealRow')
class SavedMeals extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get position => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SavedMealItemRow')
class SavedMealItems extends Table {
  TextColumn get id => text()();
  TextColumn get mealId => text().references(SavedMeals, #id)();
  IntColumn get position => integer()();
  IntColumn get foodKind => intEnum<FoodKindDb>()();
  IntColumn get usdaFdcId => integer().nullable()();
  TextColumn get customFoodId => text().nullable()();
  TextColumn get label => text()();
  RealColumn get qty => real()();
  TextColumn get unitLabel => text()();
  RealColumn get grams => real().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The recipe box. Declared* columns hold site-published per-serving
/// nutrition (schema.org), kept separate from anything computed.
@DataClassName('RecipeRow')
class Recipes extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  RealColumn get servings => real().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get instructions => text().withDefault(const Constant(''))();
  RealColumn get declaredKcal => real().nullable()();
  RealColumn get declaredProteinG => real().nullable()();
  RealColumn get declaredCarbG => real().nullable()();
  RealColumn get declaredFatG => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ingredient lines. `line` (the domain's `text`) is always kept; the food
/// match columns are nullable because matching is optional and reversible.
/// (Named `line` in storage — a column getter called `text` would shadow
/// drift's own `text()` builder.)
@DataClassName('RecipeIngredientRow')
class RecipeIngredients extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId => text().references(Recipes, #id)();
  IntColumn get position => integer()();
  TextColumn get line => text()();
  IntColumn get foodKind => intEnum<FoodKindDb>().nullable()();
  IntColumn get usdaFdcId => integer().nullable()();
  TextColumn get customFoodId => text().nullable()();
  RealColumn get grams => real().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Storage-side enums for the plan + grocery tables (same reorder-safety
/// rationale as [FoodKindDb]).
enum PlanSlotDb { breakfast, lunch, dinner, other }

enum PlanKindDb { recipe, meal, note }

enum GroceryAisleDb { produce, meat, dairy, bakery, frozen, pantry, other }

/// The week's cells: a recipe, a staple, or a note per (day, slot). Titles
/// are resolved at read time — the plan never snapshots names.
@DataClassName('PlanEntryRow')
class PlanEntries extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get day => text()();
  IntColumn get slot => intEnum<PlanSlotDb>()();
  IntColumn get kind => intEnum<PlanKindDb>()();
  TextColumn get refId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The grocery list — generated projection of the plan + manual adds.
@DataClassName('GroceryItemRow')
class GroceryItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get aisle => intEnum<GroceryAisleDb>()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  BoolColumn get manual => boolean().withDefault(const Constant(false))();
  TextColumn get sourceRecipeId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The persistent regulars record — the habit behind the one-tap rail.
/// Every diary log upserts a row (count + newest snapshot); diary deletion
/// never touches it: the ledger is what you ate, this is what you reach for.
/// Keyed by FoodRef.identityKey. Local-only by design — it derives from the
/// diary, and the plate is yours (no SyncColumns).
@DataClassName('FoodUsageRow')
class FoodUsages extends Table {
  TextColumn get identityKey => text()();
  IntColumn get foodKind => intEnum<FoodKindDb>()();
  IntColumn get usdaFdcId => integer().nullable()();
  TextColumn get customFoodId => text().nullable()();
  TextColumn get label => text()();
  RealColumn get qty => real()();
  TextColumn get unitLabel => text()();
  RealColumn get grams => real().nullable()();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  IntColumn get useCount => integer()();

  /// When this food was last logged — the rail sorts newest-first on it.
  DateTimeColumn get at => dateTime()();

  /// "Remove from regulars": hides from the rail without erasing the habit;
  /// logging the food again unhides it (a fresh use is a fresh signal).
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {identityKey};
}

/// Static personal targets — a single row (id = 1), all-null = no targets.
/// Deliberately NOT adaptive: numbers change when the user changes them.
@DataClassName('TargetsRow')
class Targets extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  RealColumn get kcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbG => real().nullable()();
  RealColumn get fatG => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  UserPrefs,
  UsdaFoods,
  UsdaPortions,
  CustomFoods,
  DiaryEntries,
  SavedMeals,
  SavedMealItems,
  Recipes,
  RecipeIngredients,
  PlanEntries,
  GroceryItems,
  FoodUsages,
  Targets,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'peckish',
              // Web needs to know where the sqlite3 WASM engine + drift worker
              // live (both shipped in web/); without this drift_flutter throws
              // "the `web` parameter needs to be set" at startup.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ));

  @override
  int get schemaVersion => 3;

  /// Wipe every user-data table in one transaction — the "Erase all data"
  /// path. Leaves the key→value shell prefs (theme) in place. This list grows
  /// in lockstep with the domain schema, and the backup restore-consequence
  /// copy in `backup_config.dart` must always enumerate what it erases.
  Future<void> eraseUserData() => transaction(() async {
        await delete(diaryEntries).go();
        await delete(savedMealItems).go();
        await delete(savedMeals).go();
        await delete(recipeIngredients).go();
        await delete(recipes).go();
        await delete(planEntries).go();
        await delete(groceryItems).go();
        await delete(customFoods).go();
        await delete(foodUsages).go();
        await delete(targets).go();
        // The USDA spine (usdaFoods/usdaPortions) is reference data, not user
        // data — it survives, as do the shell prefs.
      });

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: the sync columns on the five household-shared tables.
            // Drift migrations are NOT transactional (the StillLife lesson:
            // a mid-failure re-entry lands in half-migrated state), so each
            // ALTER is guarded by a column-existence check.
            final syncedTables = <(TableInfo, List<GeneratedColumn>)>[
              (customFoods, [customFoods.hlc, customFoods.nodeId, customFoods.isDeleted]),
              (savedMeals, [savedMeals.hlc, savedMeals.nodeId, savedMeals.isDeleted]),
              (recipes, [recipes.hlc, recipes.nodeId, recipes.isDeleted]),
              (planEntries, [planEntries.hlc, planEntries.nodeId, planEntries.isDeleted]),
              (groceryItems, [groceryItems.hlc, groceryItems.nodeId, groceryItems.isDeleted]),
            ];
            for (final (table, columns) in syncedTables) {
              for (final column in columns) {
                await _addColumnIfMissing(m, table, column);
              }
            }
          }
          if (from < 3) {
            // v3: the persistent regulars table, backfilled from the diary so
            // the rail survives the update with the user's habits intact.
            // Same non-transactional caution as v2: create + backfill run
            // only when the table is genuinely absent, so a re-entered
            // migration cannot double-count.
            if (!await _tableExists(foodUsages.actualTableName)) {
              await m.createTable(foodUsages);
              await _backfillFoodUsages();
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _addColumnIfMissing(
      Migrator m, TableInfo table, GeneratedColumn column) async {
    final info = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    final exists =
        info.any((row) => row.read<String>('name') == column.name);
    if (!exists) await m.addColumn(table, column);
  }

  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  /// One pass over the existing ledger: per food identity, the row count and
  /// the newest entry's snapshot become the seeded regular. Ascending scan —
  /// the last row seen per key is the newest.
  Future<void> _backfillFoodUsages() async {
    final rows = await (select(diaryEntries)
          ..orderBy([(e) => OrderingTerm.asc(e.at)]))
        .get();
    final counts = <String, int>{};
    final newest = <String, DiaryEntryRow>{};
    for (final r in rows) {
      final key = switch (r.foodKind) {
        FoodKindDb.usda => 'u:${r.usdaFdcId}',
        FoodKindDb.custom => 'c:${r.customFoodId}',
        FoodKindDb.quick => 'q:${r.label.toLowerCase()}',
      };
      counts[key] = (counts[key] ?? 0) + 1;
      newest[key] = r;
    }
    for (final MapEntry(key: key, value: r) in newest.entries) {
      await into(foodUsages).insert(
        FoodUsagesCompanion.insert(
          identityKey: key,
          foodKind: r.foodKind,
          usdaFdcId: Value(r.usdaFdcId),
          customFoodId: Value(r.customFoodId),
          label: r.label,
          qty: r.qty,
          unitLabel: r.unitLabel,
          grams: Value(r.grams),
          kcal: Value(r.kcal),
          proteinG: Value(r.proteinG),
          carbG: Value(r.carbG),
          fatG: Value(r.fatG),
          useCount: counts[key]!,
          at: r.at,
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }
}
