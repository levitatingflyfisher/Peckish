import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
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
    await TargetsRepository(db).set(const MacroSet(kcal: 3200, proteinG: 180));

    final blob = await serializer.dumpAll();
    await db.eraseUserData();
    expect(await diary.entriesForDay('2026-07-25'), isEmpty);

    await serializer.restoreAll(blob);

    expect((await CustomFoodRepository(db).byId('cf-1'))!.perServing.kcal, 640);
    final entries = await diary.entriesForDay('2026-07-25');
    expect(entries.single.macros.proteinG, 42);
    expect(entries.single.food.customFoodId, 'cf-1');
    final meal = (await meals.getAll()).single;
    expect(meal.items.single.label, 'Orange chicken');
    expect((await TargetsRepository(db).get()).kcal, 3200);
  });

  test('restore refuses a blob from a different app', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serializer = PeckishBackupSerializer(db);
    final foreign =
        '{"app":"lullaby","schemaVersion":1}'.codeUnits;
    expect(
      () => serializer.restoreAll(Uint8List.fromList(foreign)),
      throwsA(anything),
    );
  });

  test('the restore-consequence copy names everything eraseUserData wipes',
      () {
    final copy = peckishBackupConfig.restoreReplaceConsequence;
    // AppDatabase.eraseUserData deletes: diary entries, saved meals (+items),
    // custom foods, targets. The sentence must own each one.
    expect(copy, contains('diary'));
    expect(copy, contains('saved meal'));
    expect(copy, contains('custom food'));
    expect(copy, contains('target'));
  });
}
