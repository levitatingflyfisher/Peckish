import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../diary/data/diary_repository.dart';
import '../../diary/data/saved_meal_repository.dart';
import '../../diary/data/targets_repository.dart';
import '../../food/data/custom_food_repository.dart';
import '../../food/data/food_usage_repository.dart';
import '../../groceries/domain/grocery_item.dart';
import '../../plan/domain/plan_entry.dart';
import '../../recipes/data/recipe_repository.dart';
import '../../settings/data/export_serializer.dart';

/// Serializes Peckish's user data to/from a JSON [Uint8List] for encrypted
/// backup via `sanctuary_backup_ui`.
///
/// Wraps the plaintext-export machinery ([PeckishExport]) rather than
/// inventing a second envelope (SANCTUARY-BRIEF §4.W2). Reads/writes go
/// through the [AppDatabase] handle the caller passes in — the same one the
/// rest of the app uses, never a second connection.
///
/// [UserPrefs] (theme) and the bundled USDA spine intentionally stay OUT of
/// the backup, matching `AppDatabase.eraseUserData()`'s erase boundary: shell
/// prefs are a device preference and the spine ships with every install.
class PeckishBackupSerializer
    implements BackupSerializer, PreviewableBackupSerializer {
  final AppDatabase _db;

  const PeckishBackupSerializer(this._db);

  static const String _appId = 'peckish';

  /// Everything the app holds, as one export value — the single gathering
  /// path shared by the encrypted backup and the plain-JSON export.
  Future<PeckishExport> snapshot() async {
    final allEntries = await (_db.select(_db.diaryEntries)).get();
    final diary = DiaryRepository(_db);
    final days = allEntries.map((e) => e.day).toSet().toList()..sort();
    return PeckishExport(
      createdAt: DateTime.now(),
      customFoods:
          await CustomFoodRepository(_db).getAll(includeArchived: true),
      diaryEntries: [
        for (final day in days) ...await diary.entriesForDay(day),
      ],
      savedMeals:
          await SavedMealRepository(_db).getAll(includeArchived: true),
      recipes: await RecipeRepository(_db).getAll(includeArchived: true),
      planEntries: [
        for (final r in await (_db.select(_db.planEntries)).get())
          PlanEntry(
            id: r.id,
            day: r.day,
            slot: PlanSlot.values[r.slot.index],
            kind: PlanKind.values[r.kind.index],
            refId: r.refId,
            note: r.note,
          ),
      ],
      groceryItems: [
        for (final r in await (_db.select(_db.groceryItems)).get())
          GroceryItem(
            id: r.id,
            name: r.name,
            aisle: GroceryAisle.values[r.aisle.index],
            checked: r.checked,
            manual: r.manual,
            sourceRecipeId: r.sourceRecipeId,
            createdAt: r.createdAt,
          ),
      ],
      foodUsages: await FoodUsageRepository(_db).getAll(),
      targets: await TargetsRepository(_db).get(),
    );
  }

  @override
  Future<Uint8List> dumpAll() async {
    final export = await snapshot();
    return Uint8List.fromList(utf8.encode(export.toPrettyJson()));
  }

  /// The dry-run parse behind preview-before-restore and export
  /// verify-by-read-back: validates exactly like [restoreAll] but never
  /// writes.
  @override
  Future<BackupManifest> describeBackup(Uint8List plaintext) async {
    PeckishExport.fromMap(_unwrap(plaintext).payload);
    return BackupEnvelope.describe(plaintext);
  }

  /// Envelope validation via the shared fleet helper: rejects a blob from
  /// a different app or a future schema — defense in depth behind the AEAD
  /// context (SANCTUARY-BRIEF §2.8).
  UnwrappedBackup _unwrap(Uint8List data) => BackupEnvelope.unwrap(
        data,
        expectedAppId: _appId,
        currentSchemaVersion: PeckishExport.schemaVersion,
      );

  /// **Destructive** — wipes the user tables ([AppDatabase.eraseUserData]'s
  /// exact set) and re-inserts inside a single transaction, so a failure
  /// partway through leaves the original data intact rather than a
  /// half-restored mix (SANCTUARY-BRIEF §2.5).
  @override
  Future<void> restoreAll(Uint8List data) async {
    final export = PeckishExport.fromMap(_unwrap(data).payload);

    await _db.transaction(() async {
      // Reuses the tested erase path; drift nests this as a savepoint inside
      // the outer transaction, so a later failure rolls back the wipe too.
      await _db.eraseUserData();

      final customs = CustomFoodRepository(_db);
      for (final food in export.customFoods) {
        await customs.create(food);
      }
      final diary = DiaryRepository(_db);
      for (final entry in export.diaryEntries) {
        await diary.log(entry);
      }
      final meals = SavedMealRepository(_db);
      for (final meal in export.savedMeals) {
        await meals.create(meal);
      }
      final recipes = RecipeRepository(_db);
      for (final recipe in export.recipes) {
        await recipes.create(recipe);
      }
      for (final p in export.planEntries) {
        await _db.into(_db.planEntries).insert(PlanEntriesCompanion(
              id: Value(p.id),
              day: Value(p.day),
              slot: Value(PlanSlotDb.values[p.slot.index]),
              kind: Value(PlanKindDb.values[p.kind.index]),
              refId: Value(p.refId),
              note: Value(p.note),
            ));
      }
      for (final g in export.groceryItems) {
        await _db.into(_db.groceryItems).insert(GroceryItemsCompanion(
              id: Value(g.id),
              name: Value(g.name),
              aisle: Value(GroceryAisleDb.values[g.aisle.index]),
              checked: Value(g.checked),
              manual: Value(g.manual),
              sourceRecipeId: Value(g.sourceRecipeId),
              createdAt: Value(g.createdAt),
            ));
      }
      // Last, after the diary replay: replayed logs re-derive usage rows,
      // and the exported regulars (true counts + hidden flags — not
      // derivable from the ledger) overwrite them wholesale.
      final usage = FoodUsageRepository(_db);
      for (final u in export.foodUsages) {
        await usage.put(u);
      }
      await TargetsRepository(_db).set(export.targets);
    });
  }
}
