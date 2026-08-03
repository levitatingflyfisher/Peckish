import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/on_device/plate_scan.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

// Snap your plate: the on-device classifier's labels, turned into draft
// lines through the BUNDLED USDA spine — real macros, no model download,
// no network, no LLM. The StillLife law applies end to end: a label is
// either mapped to a food search or SKIPPED — never guessed at.
void main() {
  Future<PlateMatch?> lookup(String query) async => switch (query) {
        'pizza' => (
            name: 'Pizza, cheese',
            grams: 107.0,
            macros:
                const MacroSet(kcal: 285, proteinG: 12, carbG: 36, fatG: 10),
          ),
        'salad' => (
            name: 'Salad, garden',
            grams: 100.0,
            macros: const MacroSet(kcal: 20, proteinG: 1),
          ),
        _ => null,
      };

  test('a mapped label becomes a draft line with real spine macros', () async {
    final guess = await PlateScan.fromLabels(
      [(label: 'Pizza', confidence: 0.92)],
      lookup,
    );

    final food = guess.foods.single;
    expect(food.name, 'Pizza, cheese');
    expect(food.grams, 107);
    expect(food.macros.kcal, 285);
    expect(food.confidence, 0.92,
        reason: "the classifier's REAL confidence — never invented");
  });

  test('scene noise and generic labels are skipped, never guessed', () async {
    final guess = await PlateScan.fromLabels(
      [
        (label: 'Tableware', confidence: 0.98),
        (label: 'Food', confidence: 0.95),
        (label: 'Cuisine', confidence: 0.9),
        (label: 'Room', confidence: 0.8),
      ],
      lookup,
    );
    expect(guess.foods, isEmpty);
  });

  test('a label below the noise floor is dropped even when mapped', () async {
    final guess = await PlateScan.fromLabels(
      [(label: 'Pizza', confidence: 0.2)],
      lookup,
    );
    expect(guess.foods, isEmpty,
        reason: 'below 0.3 the base model emits scene noise');
  });

  test('a mapped label with no spine hit yields nothing, not a fake line',
      () async {
    final guess = await PlateScan.fromLabels(
      [(label: 'Sushi', confidence: 0.9)],
      lookup, // knows no sushi
    );
    expect(guess.foods, isEmpty);
  });

  test('duplicate labels collapse to one line, best confidence first',
      () async {
    final guess = await PlateScan.fromLabels(
      [
        (label: 'Salad', confidence: 0.5),
        (label: 'Pizza', confidence: 0.9),
        (label: 'pizza', confidence: 0.7),
      ],
      lookup,
    );

    expect(guess.foods, hasLength(2));
    expect(guess.foods.first.name, 'Pizza, cheese',
        reason: 'ordered by confidence');
    expect(guess.foods.first.confidence, 0.9,
        reason: 'the duplicate keeps its best sighting');
  });

  test('a plate is at most four lines', () async {
    Future<PlateMatch?> generous(String q) async =>
        (name: q, grams: 100.0, macros: const MacroSet(kcal: 100));
    final guess = await PlateScan.fromLabels(
      [
        (label: 'Pizza', confidence: 0.9),
        (label: 'Salad', confidence: 0.8),
        (label: 'Bread', confidence: 0.7),
        (label: 'Cheese', confidence: 0.6),
        (label: 'Egg', confidence: 0.5),
        (label: 'Fruit', confidence: 0.4),
      ],
      generous,
    );
    expect(guess.foods, hasLength(4));
  });

  test('no labels → an empty guess the sheet can state calmly', () async {
    final guess = await PlateScan.fromLabels(const [], lookup);
    expect(guess.foods, isEmpty);
  });
}
