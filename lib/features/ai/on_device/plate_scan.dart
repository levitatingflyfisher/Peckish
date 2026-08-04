import 'package:peckish/features/ai/domain/meal_guess.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// The classifier itself can't run here — on Android that means Google
/// Play services (which hosts ML Kit's bundled labeler) is absent or
/// broken, the normal state of a de-Googled phone. A typed exception so
/// the sheet can say exactly that, and what still works.
class PlateUnavailableException implements Exception {
  const PlateUnavailableException();
}

/// One sighting from the on-device classifier.
typedef DetectedLabel = ({String label, double confidence});

/// One spine hit: a real food with real macros at a real portion.
typedef PlateMatch = ({String name, double? grams, MacroSet macros});

/// Snap your plate — the zero-download CV rung. The on-device classifier's
/// labels become draft lines through the BUNDLED USDA spine: no network,
/// no LLM, no model file, works on any supported phone from first launch.
///
/// The StillLife law applies end to end: a label is either MAPPED to a
/// food search or SKIPPED — never guessed at. Generic scene words (Food,
/// Tableware, Cuisine…) are deliberately unmapped, and the confidence
/// shown is the classifier's real number, never an invention.
class PlateScan {
  /// Below this the base model emits scene noise ('Room', 'Floor') — the
  /// StillLife-measured floor.
  static const noiseFloor = 0.3;

  /// A plate, not a buffet.
  static const maxLines = 4;

  /// ML Kit base-labeler food labels → USDA spine search terms. Curated by
  /// hand (lowercase keys); anything absent is skipped. Generic scene and
  /// meal-occasion words stay OUT on purpose.
  /// ML Kit label → the term to search the bundled USDA spine for.
  ///
  /// EVERY key here is a label the shipped labeler can actually emit —
  /// pinned against `test/fixtures/mlkit_image_labels.txt`, its published
  /// 430-label vocabulary. The first version of this map was written from
  /// imagination: 30 of its 40 keys named labels ML Kit has never had
  /// ('sandwich', 'salad', 'chicken', 'rice'…), so on a real plate nothing
  /// matched and the sheet said no food was seen.
  ///
  /// Note how short this is. The base labeler is a general scene
  /// classifier, not a food model — roughly nineteen edible things in four
  /// hundred and thirty. That is the honest ceiling of rung 1.
  static const labelSearches = <String, String>{
    'bento': 'rice cooked',
    'bread': 'bread',
    'cake': 'cake',
    'cappuccino': 'coffee with milk',
    'cheeseburger': 'cheeseburger',
    'coffee': 'coffee',
    'cola': 'cola',
    'cookie': 'cookie',
    'couscous': 'couscous cooked',
    'fruit': 'fruit salad',
    'gelato': 'ice cream',
    'hot dog': 'frankfurter',
    'juice': 'orange juice',
    'pho': 'soup noodle',
    'pie': 'pie',
    'pizza': 'pizza',
    'sushi': 'sushi',
    'vegetable': 'vegetables mixed',
    'wine': 'wine',
  };

  /// Labels that say "this is food" without saying which food.
  ///
  /// These are the commonest sightings on a photograph of a meal, and they
  /// are deliberately NOT in [labelSearches] — guessing a specific food
  /// from 'Food' would be fabrication. But they are not nothing either,
  /// and telling someone no food was seen when the labeler reported Food
  /// at 0.94 is simply untrue. [sawFoodButNotWhat] is how the sheet tells
  /// the difference.
  static const genericFoodLabels = <String>{
    'food',
    'cuisine',
    'fast food',
    'lunch',
    'supper',
  };

  /// True when the labeler was confident something edible is in the frame
  /// but nothing specific enough to look up came back.
  ///
  /// The distinction the user actually feels: "there is no food here" and
  /// "I can see it is a meal, I just cannot name it" deserve different
  /// sentences and different next steps.
  static bool sawFoodButNotWhat(List<DetectedLabel> labels) {
    var generic = false;
    for (final l in labels) {
      if (l.confidence < noiseFloor) continue;
      if (labelSearches.containsKey(l.label.toLowerCase())) return false;
      if (genericFoodLabels.contains(l.label.toLowerCase())) generic = true;
    }
    return generic;
  }

  /// Labels in, drafts out. [lookup] resolves a search term to the best
  /// spine hit (or null — a mapped label with no hit yields nothing, not
  /// a fabricated line).
  static Future<MealGuess> fromLabels(
    List<DetectedLabel> labels,
    Future<PlateMatch?> Function(String query) lookup,
  ) async {
    // Best sighting per search term (duplicate labels collapse).
    final byQuery = <String, double>{};
    for (final l in labels) {
      if (l.confidence < noiseFloor) continue;
      final query = labelSearches[l.label.toLowerCase()];
      if (query == null) continue;
      final seen = byQuery[query];
      if (seen == null || l.confidence > seen) byQuery[query] = l.confidence;
    }

    final ranked = byQuery.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final foods = <GuessedFood>[];
    for (final entry in ranked) {
      if (foods.length == maxLines) break;
      final match = await lookup(entry.key);
      if (match == null) continue;
      foods.add(GuessedFood(
        name: match.name,
        grams: match.grams,
        macros: match.macros,
        confidence: entry.value,
      ));
    }
    return MealGuess(foods);
  }
}
