import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/relog.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

void main() {
  DiaryEntry template() => DiaryEntry(
        id: 'regular:c:egg',
        day: '2026-07-30',
        at: DateTime(2026, 7, 30, 8),
        food: const FoodRef.custom('egg'),
        label: 'Egg',
        qty: 1,
        unitLabel: 'egg',
        grams: 50,
        macros: const MacroSet(kcal: 72, proteinG: 6.3, carbG: 0.4, fatG: 4.8),
        source: EntrySource.tap,
        createdAt: DateTime(2026, 7, 30, 8),
      );

  final now = DateTime(2026, 8, 2, 19, 40);

  test('a relog with no day lands on today, at the real moment', () {
    final entry = relogEntry(template(), now: now);

    expect(entry.day, '2026-08-02');
    expect(entry.at, now);
    expect(entry.label, 'Egg');
    expect(entry.food, const FoodRef.custom('egg'));
  });

  test('a relog onto a past day lands there, and the day round-trips', () {
    final entry = relogEntry(template(), day: '2026-07-19', now: now);

    expect(entry.day, '2026-07-19');
    // The invariant the whole past-day feature rests on: a backdated line
    // must resolve back to the day it was filed under, or it sorts into one
    // day and totals into another.
    expect(DiaryEntry.dayOf(entry.at), entry.day);
  });

  test('a backdated relog still records WHEN you wrote it down', () {
    final entry = relogEntry(template(), day: '2026-07-19', now: now);

    // `at` moves to the day being fed; `createdAt` is always the real now.
    expect(entry.createdAt, now);
    expect(entry.at.isBefore(now), isTrue);
  });

  test('count scales every number that should scale, together', () {
    final entry = relogEntry(template(), count: 3, now: now);

    expect(entry.qty, 3);
    expect(entry.grams, 150);
    expect(entry.macros.kcal, closeTo(216, 0.001));
    expect(entry.macros.proteinG, closeTo(18.9, 0.001));
    // The unit is what one of them is called — it never multiplies.
    expect(entry.unitLabel, 'egg');
  });

  test('a gramless template stays gramless however many you log', () {
    // A "1 salad" custom food knows no grams — scaling must not invent any.
    final salad = DiaryEntry(
      id: 'regular:c:salad',
      day: '2026-07-30',
      at: DateTime(2026, 7, 30, 12),
      food: const FoodRef.custom('salad'),
      label: 'Cafe Rio salad',
      qty: 1,
      unitLabel: 'salad',
      grams: null,
      macros: const MacroSet(kcal: 800),
      source: EntrySource.tap,
      createdAt: DateTime(2026, 7, 30, 12),
    );

    final entry = relogEntry(salad, count: 2, now: now);

    expect(entry.grams, isNull);
    expect(entry.macros.kcal, 1600);
  });

  test('every relog is its own line, never the template', () {
    final a = relogEntry(template(), now: now);
    final b = relogEntry(template(), now: now);

    expect(a.id, isNot('regular:c:egg'));
    expect(a.id, isNot(b.id));
  });
}
