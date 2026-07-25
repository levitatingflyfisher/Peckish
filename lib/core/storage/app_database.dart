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

/// Household-defined foods. Macros are PER SERVING.
@DataClassName('CustomFoodRow')
class CustomFoods extends Table {
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

enum EntrySourceDb { tap, search, manual, ai }

/// Staples — named bundles relogged in one tap.
@DataClassName('SavedMealRow')
class SavedMeals extends Table {
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
  int get schemaVersion => 1;

  /// Wipe every user-data table in one transaction — the "Erase all data"
  /// path. Leaves the key→value shell prefs (theme) in place. This list grows
  /// in lockstep with the domain schema, and the backup restore-consequence
  /// copy in `backup_config.dart` must always enumerate what it erases.
  Future<void> eraseUserData() => transaction(() async {
        await delete(diaryEntries).go();
        await delete(savedMealItems).go();
        await delete(savedMeals).go();
        await delete(customFoods).go();
        await delete(targets).go();
        // The USDA spine (usdaFoods/usdaPortions) is reference data, not user
        // data — it survives, as do the shell prefs.
      });

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
