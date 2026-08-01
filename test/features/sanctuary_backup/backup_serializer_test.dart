import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/sanctuary_backup/backup_config.dart';
import 'package:peckish/features/sanctuary_backup/data/backup_serializer.dart';

void main() {
  test('dump → erase → restore reproduces the user dataset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serializer = PeckishBackupSerializer(db);

    await CustomFoodRepository(db).create(CustomFood(
      id: 'cf-1',
      name: 'Cafe Rio salad',
      servingLabel: '1 salad',
      perServing: const MacroSet(kcal: 640, proteinG: 42),
      createdAt: DateTime.utc(2026, 7, 1),
    ));
    final diary = DiaryRepository(db);
    await diary.log(DiaryEntry(
      id: 'e-1',
      day: '2026-07-25',
      at: DateTime.utc(2026, 7, 25, 12, 30),
      food: const FoodRef.custom('cf-1'),
      label: 'Cafe Rio salad',
      qty: 1,
      unitLabel: '1 salad',
      grams: null,
      macros: const MacroSet(kcal: 640, proteinG: 42),
      source: EntrySource.tap,
      createdAt: DateTime.utc(2026, 7, 25, 12, 30),
    ));
    final meals = SavedMealRepository(db, idGenerator: () => 'gen');
    await meals.create(SavedMeal(
      id: 'm-1',
      name: 'Panda — bad day',
      position: 0,
      createdAt: DateTime.utc(2026, 7, 2),
      items: [
        const SavedMealItem(
          id: 'i-1',
          food: FoodRef.quick(),
          label: 'Orange chicken',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: MacroSet(kcal: 490),
        ),
      ],
    ));
    // An explicit role: like the hidden flag below, it is NOT derivable
    // from the diary replay — the backup must carry it through.
    await TargetsRepository(db).set(const DailyTargets(
      values: MacroSet(kcal: 3200, proteinG: 180),
      kcalRole: TargetRole.under,
    ));
    // A hidden regular: its count + hidden flag are NOT derivable from the
    // diary replay — the backup must carry them through.
    final usage = FoodUsageRepository(db);
    await usage.setHidden('c:cf-1', hidden: true);

    final blob = await serializer.dumpAll();
    await db.eraseUserData();
    expect(await diary.entriesForDay('2026-07-25'), isEmpty);
    expect(await usage.getAll(), isEmpty);

    await serializer.restoreAll(blob);

    expect((await CustomFoodRepository(db).byId('cf-1'))!.perServing.kcal, 640);
    final entries = await diary.entriesForDay('2026-07-25');
    expect(entries.single.macros.proteinG, 42);
    expect(entries.single.food.customFoodId, 'cf-1');
    final meal = (await meals.getAll()).single;
    expect(meal.items.single.label, 'Orange chicken');
    final targets = await TargetsRepository(db).get();
    expect(targets.values.kcal, 3200);
    expect(targets.kcalRole, TargetRole.under,
        reason: 'roles survive the backup round-trip');
    expect(targets.proteinRole, isNull,
        reason: 'an unset role restores unset, not invented');
    final restored = await usage.getAll();
    expect(restored.single.identityKey, 'c:cf-1');
    expect(restored.single.hidden, isTrue,
        reason: 'the exported regular overrides the replay-derived row');
  });

  // v0.6 shipped a bug here: snapshot() and restoreAll() hand-mapped the
  // plan/grocery tables instead of going through their repositories — so a
  // tombstoned (deleted) row was exported as LIVE, and restored rows came
  // back UNSTAMPED (invisible to LWW sync until the stampUnstamped
  // backfill). The serializer now routes through PlanRepository /
  // GroceryRepository, inheriting their isDeleted filter and HLC stamping.
  group('tombstones and stamping:', () {
    test('a deleted grocery item does not ride along in the export', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final groceries = GroceryRepository(db);
      await groceries.addManual('Bananas');
      await groceries.addManual('Regretted kombucha');
      final doomed = (await groceries.getAll())
          .firstWhere((g) => g.name == 'Regretted kombucha');
      await groceries.remove(doomed.id);

      final json = utf8.decode(await PeckishBackupSerializer(db).dumpAll());
      expect(json, contains('Bananas'), reason: 'live rows still export');
      expect(json, isNot(contains('Regretted kombucha')),
          reason: 'a tombstone is a deletion, not a grocery');
    });

    test('a removed plan cell does not ride along in the export', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final plan = PlanRepository(db);
      await plan.upsert(const PlanEntry(
          id: 'p-live',
          day: '2026-08-03',
          slot: PlanSlot.dinner,
          kind: PlanKind.note,
          note: 'Tacos'));
      await plan.upsert(const PlanEntry(
          id: 'p-doomed',
          day: '2026-08-04',
          slot: PlanSlot.dinner,
          kind: PlanKind.note,
          note: 'Cancelled fondue'));
      await plan.remove('p-doomed');

      final json = utf8.decode(await PeckishBackupSerializer(db).dumpAll());
      expect(json, contains('Tacos'), reason: 'live cells still export');
      expect(json, isNot(contains('Cancelled fondue')),
          reason: 'a removed cell must not restore as a live plan');
      expect(json, isNot(contains('p-doomed')));
    });

    test('restored plan and grocery rows come back stamped for sync', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final serializer = PeckishBackupSerializer(db);
      await GroceryRepository(db).addManual('Milk');
      await PlanRepository(db).upsert(const PlanEntry(
          id: 'p-1',
          day: '2026-08-03',
          slot: PlanSlot.lunch,
          kind: PlanKind.note,
          note: 'Leftovers'));

      final blob = await serializer.dumpAll();
      await db.eraseUserData();
      await serializer.restoreAll(blob);

      final grocery = await db.select(db.groceryItems).getSingle();
      expect(grocery.hlc, isNotEmpty,
          reason: 'an unstamped row can only ever fill a hole on a peer');
      expect(grocery.nodeId, isNotEmpty);
      final cell = await db.select(db.planEntries).getSingle();
      expect(cell.hlc, isNotEmpty);
      expect(cell.nodeId, isNotEmpty);
      expect(await SyncEngine(db).stampUnstamped(), 0,
          reason: 'a restore leaves nothing for the backfill to find');
    });
  });

  test('restore refuses a blob from a different app', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serializer = PeckishBackupSerializer(db);
    final foreign = '{"app":"lullaby","schemaVersion":1}'.codeUnits;
    expect(
      () => serializer.restoreAll(Uint8List.fromList(foreign)),
      throwsA(anything),
    );
  });

  test('the restore-consequence copy names everything eraseUserData wipes', () {
    final copy = peckishBackupConfig.restoreReplaceConsequence;
    // AppDatabase.eraseUserData deletes: diary entries, saved meals (+items),
    // recipes (+ingredients), custom foods, targets. The sentence must own
    // each one.
    expect(copy, contains('diary'));
    expect(copy, contains('saved meal'));
    expect(copy, contains('custom food'));
    expect(copy, contains('regular'));
    expect(copy, contains('recipe'));
    expect(copy, contains('plan'));
    expect(copy, contains('grocery'));
    expect(copy, contains('target'));
  });
}
