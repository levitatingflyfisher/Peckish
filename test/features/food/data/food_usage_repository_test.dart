import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

// The phone-test bug this file pins: "common items get deleted if all of the
// day's instances of using them get deleted." Regulars are their own
// persistent record now — the diary is the ledger, usage is the habit, and
// erasing lines from one never erases the other.

DiaryEntry entry({
  required String id,
  String label = 'Oatmeal',
  DateTime? at,
  MacroSet macros = const MacroSet(kcal: 150, proteinG: 5),
}) {
  final when = at ?? DateTime(2026, 7, 1, 8);
  return DiaryEntry(
    id: id,
    day: DiaryEntry.dayOf(when),
    at: when,
    food: const FoodRef.quick(),
    label: label,
    qty: 1,
    unitLabel: 'serving',
    grams: null,
    macros: macros,
    source: EntrySource.manual,
    createdAt: when,
  );
}

void main() {
  late AppDatabase db;
  late DiaryRepository diary;
  late FoodUsageRepository usage;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    diary = DiaryRepository(db);
    usage = FoodUsageRepository(db);
  });

  tearDown(() => db.close());

  test('logging a line records the regular: count 1, snapshot, lastUsedAt',
      () async {
    await diary.log(entry(id: 'e-1'));
    final regulars = await usage.regulars();
    expect(regulars, hasLength(1));
    expect(regulars.single.label, 'Oatmeal');
    expect(regulars.single.useCount, 1);
    expect(regulars.single.lastUsedAt, DateTime(2026, 7, 1, 8));
    expect(regulars.single.macros.kcal, 150);
  });

  test('relogging increments the count and keeps the newest snapshot',
      () async {
    await diary.log(entry(id: 'e-1', at: DateTime(2026, 7, 1)));
    await diary.log(entry(
        id: 'e-2',
        at: DateTime(2026, 7, 2),
        macros: const MacroSet(kcal: 160)));
    final regulars = await usage.regulars();
    expect(regulars.single.useCount, 2);
    expect(regulars.single.lastUsedAt, DateTime(2026, 7, 2));
    expect(regulars.single.macros.kcal, 160);
  });

  test('an out-of-order older entry never rolls back the newest snapshot',
      () async {
    await diary.log(entry(id: 'e-1', at: DateTime(2026, 7, 2)));
    await diary.log(entry(
        id: 'e-2',
        at: DateTime(2026, 7, 1),
        macros: const MacroSet(kcal: 999)));
    final regulars = await usage.regulars();
    expect(regulars.single.useCount, 2);
    expect(regulars.single.lastUsedAt, DateTime(2026, 7, 2));
    expect(regulars.single.macros.kcal, 150);
  });

  test('THE bug: deleting every diary instance leaves the regular standing',
      () async {
    await diary.log(entry(id: 'e-1'));
    await diary.delete('e-1');
    expect(await diary.entriesForDay('2026-07-01'), isEmpty);
    final regulars = await usage.regulars();
    expect(regulars, hasLength(1));
    expect(regulars.single.label, 'Oatmeal');
  });

  test('recents() serves from the persistent regulars, newest first', () async {
    await diary
        .log(entry(id: 'e-1', label: 'Oatmeal', at: DateTime(2026, 7, 1)));
    await diary.log(entry(id: 'e-2', label: 'Eggs', at: DateTime(2026, 7, 2)));
    await diary.delete('e-2'); // deletion must not reorder or remove
    final recents = await diary.recents();
    expect(recents.map((e) => e.label).toList(), ['Eggs', 'Oatmeal']);
  });

  test('hide removes a regular from the rail; logging it again unhides',
      () async {
    await diary.log(entry(id: 'e-1'));
    final key = (await usage.regulars()).single.identityKey;

    await usage.setHidden(key, hidden: true);
    expect(await usage.regulars(), isEmpty);
    expect(await diary.recents(), isEmpty);
    expect(await usage.regulars(includeHidden: true), hasLength(1));

    await diary.log(entry(id: 'e-2', at: DateTime(2026, 7, 3)));
    expect(await usage.regulars(), hasLength(1));
  });

  test('a regular relogs as a template entry with its snapshot', () async {
    await diary.log(entry(id: 'e-1'));
    final template = (await diary.recents()).single;
    expect(template.label, 'Oatmeal');
    expect(template.qty, 1);
    expect(template.unitLabel, 'serving');
    expect(template.macros.kcal, 150);
    expect(template.food.kind, FoodKind.quick);
  });

  test('watchVisible: hidden stays out, newest first, LIMIT in the query',
      () async {
    await diary
        .log(entry(id: 'e-1', label: 'Oatmeal', at: DateTime(2026, 7, 1)));
    await diary.log(entry(id: 'e-2', label: 'Eggs', at: DateTime(2026, 7, 2)));
    await diary.log(entry(id: 'e-3', label: 'Toast', at: DateTime(2026, 7, 3)));
    await usage.setHidden('q:toast', hidden: true);

    final visible = await usage.watchVisible().first;
    expect(visible.map((u) => u.label).toList(), ['Eggs', 'Oatmeal'],
        reason: 'hidden regulars stay out; the rest come newest first');

    final capped = await usage.watchVisible(limit: 1).first;
    expect(capped.map((u) => u.label).toList(), ['Eggs'],
        reason: 'the cap is respected inside the query');
  });

  test('watchTopUsed: most-used first, label breaks ties, visible-only cap',
      () async {
    // Oatmeal x2; Banana, Eggs, Toast x1 each; Toast then hidden.
    await diary
        .log(entry(id: 'e-1', label: 'Oatmeal', at: DateTime(2026, 7, 1)));
    await diary
        .log(entry(id: 'e-2', label: 'Oatmeal', at: DateTime(2026, 7, 2)));
    await diary.log(entry(id: 'e-3', label: 'Eggs', at: DateTime(2026, 7, 3)));
    await diary.log(entry(id: 'e-4', label: 'Toast', at: DateTime(2026, 7, 4)));
    await diary
        .log(entry(id: 'e-5', label: 'Banana', at: DateTime(2026, 7, 5)));
    await usage.setHidden('q:toast', hidden: true);

    final top = await usage.watchTopUsed(limit: 2).first;
    expect(top.map((u) => u.label).toList(), ['Oatmeal', 'Banana'],
        reason: 'count first, then label a-z (Banana beats Eggs); hidden '
            'excluded before the cap; LIMIT respected');
  });

  test('logging a saved meal records usage for each item', () async {
    final meals = SavedMealRepository(db);
    await meals.create(SavedMeal(
      id: 'm-1',
      name: 'Breakfast',
      position: 0,
      createdAt: DateTime(2026, 7, 1),
      items: const [
        SavedMealItem(
          id: 'i-1',
          food: FoodRef.quick(),
          label: 'Toast',
          qty: 2,
          unitLabel: 'slice',
          grams: null,
          macros: MacroSet(kcal: 140),
        ),
        SavedMealItem(
          id: 'i-2',
          food: FoodRef.quick(),
          label: 'Juice',
          qty: 1,
          unitLabel: 'glass',
          grams: null,
          macros: MacroSet(kcal: 110),
        ),
      ],
    ));
    await meals.logMeal('m-1', at: DateTime(2026, 7, 2, 8), day: '2026-07-02');
    final labels = (await usage.regulars()).map((u) => u.label).toSet();
    expect(labels, {'Toast', 'Juice'});
  });
}
