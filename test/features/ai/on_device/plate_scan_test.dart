import 'dart:io';
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
        'vegetables mixed' => (
            name: 'Vegetables, mixed',
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
        (label: 'Vegetable', confidence: 0.5),
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
        (label: 'Sushi', confidence: 0.8),
        (label: 'Bread', confidence: 0.7),
        (label: 'Cake', confidence: 0.6),
        (label: 'Cookie', confidence: 0.5),
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

  group('the label map must describe the labeler we actually ship', () {
    // The phone report: "the local model downloaded but guess-my-plate just
    // fails." It was not crashing. The map was written from imagination
    // rather than from ML Kit's published vocabulary, so 30 of its 40 keys
    // named labels the labeler can never emit — while `Food`, the label most
    // likely to fire on a photo of a plate, was absent. Every real plate
    // produced zero lines and a message saying no food was seen.
    late Set<String> vocabulary;

    setUpAll(() {
      vocabulary = File('test/fixtures/mlkit_image_labels.txt')
          .readAsLinesSync()
          .map((l) => l.trim().toLowerCase())
          .where((l) => l.isNotEmpty)
          .toSet();
      // Guard the guard: an empty fixture would make every assertion below
      // pass for free.
      expect(vocabulary.length, greaterThan(400));
      expect(vocabulary, contains('food'));
    });

    test('every mapped key is a label ML Kit can actually emit', () {
      final dead = PlateScan.labelSearches.keys
          .where((k) => !vocabulary.contains(k))
          .toList();
      expect(dead, isEmpty,
          reason: 'these keys can never fire — the labeler has no such '
              'label: ${dead.join(', ')}');
    });

    test('the generic labels are known, not merely unmapped', () {
      // "Food" must not be silently absent. It is the commonest sighting on
      // a plate, and the difference between "I saw nothing" and "I saw food
      // but cannot say what" is the whole message the user reads.
      for (final generic in PlateScan.genericFoodLabels) {
        expect(vocabulary, contains(generic),
            reason: '$generic is claimed generic but ML Kit never emits it');
      }
      expect(PlateScan.genericFoodLabels, contains('food'));
    });

    test('a plate seen only generically is reported as such, not as empty',
        () async {
      final guess = await PlateScan.fromLabels(
        [
          (label: 'Food', confidence: 0.94),
          (label: 'Cuisine', confidence: 0.7)
        ],
        (_) async => null,
      );
      expect(guess.foods, isEmpty);
      expect(
          PlateScan.sawFoodButNotWhat(
            [(label: 'Food', confidence: 0.94)],
          ),
          isTrue,
          reason: 'telling someone no food was seen, when the labeler '
              'reported Food at 0.94, is simply untrue');
    });

    test('a genuinely empty scene is NOT reported as food', () {
      expect(
          PlateScan.sawFoodButNotWhat(
            [(label: 'Sink', confidence: 0.9), (label: 'Toy', confidence: 0.5)],
          ),
          isFalse);
      expect(PlateScan.sawFoodButNotWhat(const []), isFalse);
    });

    test('a generic sighting below the noise floor does not count', () {
      expect(PlateScan.sawFoodButNotWhat([(label: 'Food', confidence: 0.05)]),
          isFalse);
    });
  });
}
