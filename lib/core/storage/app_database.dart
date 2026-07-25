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

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [UserPrefs, UsdaFoods, UsdaPortions])
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
        // No domain tables yet — the food/diary/recipe/plan tables land with
        // their features and are added here in the same commit.
      });

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
