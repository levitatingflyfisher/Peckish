import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/suggestion_engine.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

// "Round out your day": from the foods you actually eat (the regulars
// record), which small combination best finishes today's targets? The
// scorer honors roles asymmetrically — a floor only hurts when short, a
// cap only when over — which is what "prioritize protein" really means.
// The engine is pure and deterministic: same plate, same advice.
FoodUsage food(String label, MacroSet macros, {int useCount = 1}) => FoodUsage(
      identityKey: 'q:${label.toLowerCase()}',
      food: const FoodRef.quick(),
      label: label,
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      useCount: useCount,
      lastUsedAt: DateTime.utc(2026, 7, 28),
      hidden: false,
    );

void main() {
  const engine = SuggestionEngine();

  test('no targets set → nothing to say', () {
    final r = engine.suggest(
      targets: const DailyTargets(),
      eaten: const MacroSet(kcal: 500),
      regulars: [food('Egg', const MacroSet(kcal: 90, proteinG: 13))],
    );
    expect(r.status, SuggestionStatus.noTargets);
    expect(r.ideas, isEmpty);
  });

  test('a finished day is called finished, not padded further', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(kcal: 2000, proteinG: 150)),
      eaten: const MacroSet(kcal: 1980, proteinG: 155),
      regulars: [food('Egg', const MacroSet(kcal: 90, proteinG: 13))],
    );
    expect(r.status, SuggestionStatus.complete);
    expect(r.ideas, isEmpty);
  });

  test('already over an about-target → quiet, never a scold', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(kcal: 2000)),
      eaten: const MacroSet(kcal: 2600),
      regulars: [food('Apple', const MacroSet(kcal: 80))],
    );
    expect(r.status, SuggestionStatus.quiet,
        reason: 'food only adds; when nothing helps, the card is silent');
    expect(r.ideas, isEmpty);
  });

  test('no regulars yet → quiet', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(proteinG: 150)),
      eaten: const MacroSet(proteinG: 100),
      regulars: const [],
    );
    expect(r.status, SuggestionStatus.quiet);
  });

  test('a protein floor pulls protein-dense regulars, not filler', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(proteinG: 150)),
      eaten: const MacroSet(proteinG: 120, kcal: 1500),
      regulars: [
        food('Greek yogurt', const MacroSet(kcal: 120, proteinG: 20),
            useCount: 10),
        food('Chips', const MacroSet(kcal: 300, proteinG: 2), useCount: 5),
      ],
    );
    expect(r.status, SuggestionStatus.ideas);
    final labels = r.ideas.first.items.map((i) => i.usage.label).toSet();
    expect(labels, {'Greek yogurt'});
    expect(r.ideas.first.completesDay, isTrue,
        reason: '30g short, two yogurts close it');
  });

  test('multiplicity is natural: three eggs are a valid answer', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(proteinG: 40)),
      eaten: const MacroSet(),
      regulars: [food('Egg', const MacroSet(kcal: 90, proteinG: 13))],
    );
    expect(r.status, SuggestionStatus.ideas);
    final top = r.ideas.first;
    expect(top.items.single.usage.label, 'Egg');
    expect(top.items.single.count, 3,
        reason: '3 × 13g = 39g meets the floor within tolerance');
    expect(top.completesDay, isTrue);
  });

  test('complementary pairs beat every single when no single can close', () {
    // 500 kcal about-gap AND a 40g protein floor: rice alone leaves protein
    // short, chicken alone leaves kcal short. Together they land the day.
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(kcal: 2000, proteinG: 150)),
      eaten: const MacroSet(kcal: 1500, proteinG: 110),
      regulars: [
        food('Rice bowl', const MacroSet(kcal: 250, proteinG: 5)),
        food('Chicken breast', const MacroSet(kcal: 250, proteinG: 35)),
      ],
    );
    expect(r.status, SuggestionStatus.ideas);
    final top = r.ideas.first;
    expect(top.items, hasLength(greaterThan(1)),
        reason: 'the sum points where no single item can');
    final labels = top.items.map((i) => i.usage.label).toSet();
    expect(labels, contains('Chicken breast'));
    expect(top.completesDay, isTrue);
  });

  test('a cap is respected: the 800-kcal burrito is never the answer', () {
    final r = engine.suggest(
      targets: const DailyTargets(
        values: MacroSet(kcal: 2000, proteinG: 150),
        kcalRole: TargetRole.under,
      ),
      eaten: const MacroSet(kcal: 1900, proteinG: 130),
      regulars: [
        food('Burrito', const MacroSet(kcal: 800, proteinG: 30)),
        food('Protein shake', const MacroSet(kcal: 110, proteinG: 25)),
      ],
    );
    expect(r.status, SuggestionStatus.ideas);
    for (final idea in r.ideas) {
      final labels = idea.items.map((i) => i.usage.label);
      expect(labels, isNot(contains('Burrito')),
          reason: 'blowing an under-cap by 700 kcal can never score well');
    }
  });

  test('overshooting a floor is free — the floor does not cap', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(proteinG: 40)),
      eaten: const MacroSet(proteinG: 35),
      regulars: [food('Steak', const MacroSet(kcal: 400, proteinG: 50))],
    );
    expect(r.status, SuggestionStatus.ideas,
        reason: 'a steak lands 85g on a 40g floor — over a floor is fine');
    expect(r.ideas.first.completesDay, isTrue);
  });

  test('familiarity breaks ties between equal fits', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(proteinG: 40)),
      eaten: const MacroSet(proteinG: 20),
      regulars: [
        food('New bar', const MacroSet(kcal: 200, proteinG: 20), useCount: 1),
        food('Old faithful', const MacroSet(kcal: 200, proteinG: 20),
            useCount: 40),
      ],
    );
    expect(r.status, SuggestionStatus.ideas);
    expect(r.ideas.first.items.first.usage.label, 'Old faithful');
  });

  test('ideas are diverse: not three variations on the same yogurt', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(kcal: 2000, proteinG: 150)),
      eaten: const MacroSet(kcal: 1400, proteinG: 100),
      regulars: [
        food('Yogurt', const MacroSet(kcal: 120, proteinG: 20), useCount: 9),
        food('Eggs on toast', const MacroSet(kcal: 300, proteinG: 22),
            useCount: 7),
        food('Cottage cheese', const MacroSet(kcal: 180, proteinG: 24),
            useCount: 5),
      ],
    );
    expect(r.status, SuggestionStatus.ideas);
    expect(r.ideas.length, greaterThan(1));
    final leads = [for (final s in r.ideas) s.items.first.usage.label];
    expect(leads.toSet().length, leads.length,
        reason: 'each idea opens with a different food');
  });

  test('same plate, same advice — deterministic output', () {
    DaySuggestions run() => engine.suggest(
          targets:
              const DailyTargets(values: MacroSet(kcal: 2000, proteinG: 150)),
          eaten: const MacroSet(kcal: 1200, proteinG: 80),
          regulars: [
            food('A', const MacroSet(kcal: 200, proteinG: 15), useCount: 3),
            food('B', const MacroSet(kcal: 350, proteinG: 30), useCount: 2),
            food('C', const MacroSet(kcal: 150, proteinG: 3), useCount: 8),
          ],
        );
    final first = run();
    final second = run();
    expect(first.status, second.status);
    expect(
      [
        for (final s in first.ideas)
          [for (final i in s.items) '${i.usage.label}×${i.count}'].join('+')
      ],
      [
        for (final s in second.ideas)
          [for (final i in s.items) '${i.usage.label}×${i.count}'].join('+')
      ],
    );
  });

  test('an all-null-macro regular can never be suggested', () {
    final r = engine.suggest(
      targets: const DailyTargets(values: MacroSet(kcal: 2000)),
      eaten: const MacroSet(kcal: 1500),
      regulars: [
        food('Mystery meal', const MacroSet()),
        food('Apple', const MacroSet(kcal: 80)),
      ],
    );
    for (final idea in r.ideas) {
      expect(
          idea.items.map((i) => i.usage.label), isNot(contains('Mystery meal')),
          reason: 'no numbers, no basis to suggest it');
    }
  });
}
