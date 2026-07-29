import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

DiaryEntry entry({
  String id = 'e-1',
  String day = '2026-07-25',
  String label = 'Egg burrito',
  double qty = 1,
  MacroSet macros = const MacroSet(kcal: 249, proteinG: 10.9, carbG: 20.1, fatG: 13.7),
  int? usdaFdcId = 2707343,
  DateTime? at,
}) =>
    DiaryEntry(
      id: id,
      day: day,
      at: at ?? DateTime(2026, 7, 25, 8, 30),
      food: usdaFdcId != null
          ? FoodRef.usda(usdaFdcId)
          : const FoodRef.quick(),
      label: label,
      qty: qty,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      source: EntrySource.search,
      createdAt: at ?? DateTime(2026, 7, 25, 8, 30),
    );

void main() {
  late AppDatabase db;
  late DiaryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DiaryRepository(db);
  });

  tearDown(() => db.close());

  test('log two entries → the day totals are exact sums', () async {
    await repo.log(entry());
    await repo.log(entry(
      id: 'e-2',
      label: 'Cheese, cheddar',
      macros: const MacroSet(kcal: 114, proteinG: 7.1, carbG: 0.4, fatG: 9.4),
    ));
    final totals = await repo.totalsForDay('2026-07-25');
    expect(totals.kcal, closeTo(363, 0.01));
    expect(totals.proteinG, closeTo(18.0, 0.01));
  });

  test('an entry missing a slot never fake-zeroes the day', () async {
    await repo.log(entry(macros: const MacroSet(kcal: 700)));
    final totals = await repo.totalsForDay('2026-07-25');
    expect(totals.kcal, 700);
    expect(totals.proteinG, isNull);
  });

  test('days are isolated', () async {
    await repo.log(entry());
    await repo.log(entry(id: 'e-2', day: '2026-07-26'));
    expect((await repo.entriesForDay('2026-07-25')), hasLength(1));
    expect((await repo.entriesForDay('2026-07-26')), hasLength(1));
    expect((await repo.entriesForDay('2026-07-24')), isEmpty);
  });

  test('update edits an entry in place', () async {
    await repo.log(entry());
    final logged = (await repo.entriesForDay('2026-07-25')).single;
    await repo.update(logged.copyWith(qty: 2, macros: logged.macros * 2));
    final edited = (await repo.entriesForDay('2026-07-25')).single;
    expect(edited.qty, 2);
    expect(edited.macros.kcal, closeTo(498, 0.01));
  });

  test('delete removes an entry — no soft-delete ceremony', () async {
    await repo.log(entry());
    await repo.delete('e-1');
    expect(await repo.entriesForDay('2026-07-25'), isEmpty);
  });

  test('recents dedupes by food identity, most recent first', () async {
    await repo.log(entry(at: DateTime(2026, 7, 25, 8, 0)));
    await repo.log(entry(
      id: 'e-2',
      label: 'Cheese, cheddar',
      usdaFdcId: 173410,
      at: DateTime(2026, 7, 25, 9, 0),
    ));
    // the burrito again, later — should surface once, at the top
    await repo.log(entry(id: 'e-3', at: DateTime(2026, 7, 25, 12, 0)));
    final recents = await repo.recents(limit: 10);
    expect(recents, hasLength(2));
    expect(recents.first.label, 'Egg burrito');
  });

  test('watchEntriesForDay streams live updates', () async {
    final stream = repo.watchEntriesForDay('2026-07-25');
    final first = await stream.first;
    expect(first, isEmpty);
    await repo.log(entry());
    final second = await stream.firstWhere((rows) => rows.isNotEmpty);
    expect(second.single.label, 'Egg burrito');
  });

  // History reads a RANGE of days in one query; days without entries are
  // simply absent (the screen shows them as blanks, not zeros).
  test('totalsForDays sums each asked day, and only asked days', () async {
    await repo.log(entry());
    await repo.log(entry(
      id: 'e-2',
      macros: const MacroSet(kcal: 114, proteinG: 7.1),
    ));
    await repo.log(entry(
      id: 'e-3',
      day: '2026-07-26',
      macros: const MacroSet(kcal: 500),
    ));
    await repo.log(entry(
      id: 'e-4',
      day: '2026-07-20',
      macros: const MacroSet(kcal: 999),
    ));

    final totals =
        await repo.totalsForDays(['2026-07-25', '2026-07-26', '2026-07-27']);
    expect(totals.keys, unorderedEquals(['2026-07-25', '2026-07-26']),
        reason: 'an empty day is absent; an unasked day never leaks in');
    expect(totals['2026-07-25']!.kcal, closeTo(363, 0.01));
    expect(totals['2026-07-26']!.kcal, 500);
  });

  // The single-write-path law, edit half: an update flows into the
  // regulars snapshot when it touches the newest use — but an edit is not
  // a new use, so the count never moves and a hidden regular stays hidden.
  test('update heals the regular snapshot without bumping the count',
      () async {
    await repo.log(entry(qty: 1));
    await repo.update(entry(
      qty: 2,
      macros: const MacroSet(kcal: 498, proteinG: 21.8),
    ));

    final regular = (await FoodUsageRepository(db).getAll()).single;
    expect(regular.qty, 2, reason: 'the edited qty is the new snapshot');
    expect(regular.macros.kcal, 498);
    expect(regular.useCount, 1, reason: 'an edit is not a fresh use');
  });

  test('editing an older entry never rolls a newer snapshot back', () async {
    await repo.log(entry(at: DateTime(2026, 7, 25, 8)));
    await repo.log(entry(
      id: 'e-2',
      qty: 3,
      at: DateTime(2026, 7, 25, 12),
    ));

    await repo.update(entry(
      qty: 9,
      at: DateTime(2026, 7, 25, 8),
      macros: const MacroSet(kcal: 1),
    ));

    final regular = (await FoodUsageRepository(db).getAll()).single;
    expect(regular.qty, 3, reason: 'the noon entry is still the newest use');
    expect(regular.useCount, 2);
  });

  test('update leaves a hidden regular hidden', () async {
    await repo.log(entry());
    await FoodUsageRepository(db).setHidden('u:2707343', hidden: true);
    await repo.update(entry(qty: 2));
    expect((await FoodUsageRepository(db).getAll()).single.hidden, isTrue,
        reason: 'fixing a number is not reaching for the food again');
  });

  test('watchTotalsForDays streams live per-day updates', () async {
    final stream = repo.watchTotalsForDays(['2026-07-25', '2026-07-26']);
    expect(await stream.first, isEmpty);
    await repo.log(entry());
    final next = await stream.firstWhere((m) => m.isNotEmpty);
    expect(next['2026-07-25']!.kcal, 249);
  });
}
