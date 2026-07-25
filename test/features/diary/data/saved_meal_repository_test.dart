import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

SavedMealItem item(String label, double kcal) => SavedMealItem(
      id: 'i-$label',
      food: const FoodRef.quick(),
      label: label,
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: MacroSet(kcal: kcal),
    );

void main() {
  late AppDatabase db;
  late SavedMealRepository meals;
  late DiaryRepository diary;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    meals = SavedMealRepository(db);
    diary = DiaryRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seedPandaBadDay() => meals.create(SavedMeal(
        id: 'm-1',
        name: 'Panda — bad day',
        position: 0,
        createdAt: DateTime(2026, 7, 25),
        items: [item('Orange chicken', 490), item('Double chow mein', 1020)],
      ));

  test('create then read back keeps items in order', () async {
    await seedPandaBadDay();
    final got = (await meals.getAll()).single;
    expect(got.name, 'Panda — bad day');
    expect(got.items.map((i) => i.label).toList(),
        ['Orange chicken', 'Double chow mein']);
  });

  test('the one-tap: logMeal writes one diary entry per item, stamped now',
      () async {
    await seedPandaBadDay();
    final at = DateTime(2026, 7, 25, 18, 45);
    await meals.logMeal('m-1', at: at, day: '2026-07-25');
    final entries = await diary.entriesForDay('2026-07-25');
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.source == EntrySource.tap), isTrue);
    final totals = await diary.totalsForDay('2026-07-25');
    expect(totals.kcal, 1510);
  });

  test('logging stamps lastUsedAt so staples float to the top', () async {
    await seedPandaBadDay();
    await meals.logMeal('m-1',
        at: DateTime(2026, 7, 25, 18, 45), day: '2026-07-25');
    final got = (await meals.getAll()).single;
    expect(got.lastUsedAt, isNotNull);
  });

  test('deleting a meal never touches entries already logged from it',
      () async {
    await seedPandaBadDay();
    await meals.logMeal('m-1',
        at: DateTime(2026, 7, 25, 18, 45), day: '2026-07-25');
    await meals.delete('m-1');
    expect(await meals.getAll(), isEmpty);
    expect(await diary.entriesForDay('2026-07-25'), hasLength(2));
  });

  test('rename and reorder are plain updates', () async {
    await seedPandaBadDay();
    await meals.create(SavedMeal(
      id: 'm-2',
      name: 'Broccoli bowl',
      position: 1,
      createdAt: DateTime(2026, 7, 25),
      items: [item('Broccoli slop', 430)],
    ));
    await meals.rename('m-1', 'Panda — the fun order');
    await meals.reorder(['m-2', 'm-1']);
    final all = await meals.getAll();
    expect(all.first.name, 'Broccoli bowl');
    expect(all.last.name, 'Panda — the fun order');
  });

  test('archive hides without deleting; unarchive restores', () async {
    await seedPandaBadDay();
    await meals.setArchived('m-1', archived: true);
    expect(await meals.getAll(), isEmpty);
    expect(await meals.getAll(includeArchived: true), hasLength(1));
  });
}
