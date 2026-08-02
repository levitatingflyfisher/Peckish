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
  static const labelSearches = <String, String>{
    'apple': 'apple raw',
    'bacon': 'bacon',
    'banana': 'banana raw',
    'bread': 'bread',
    'burrito': 'burrito',
    'cake': 'cake',
    'candy': 'candy',
    'cheese': 'cheese cheddar',
    'chicken': 'chicken',
    'chocolate': 'chocolate',
    'coffee': 'coffee',
    'cookie': 'cookie',
    'crumpet': 'english muffin',
    'curry': 'curry',
    'dessert': 'dessert',
    'egg': 'egg',
    'fruit': 'fruit salad',
    'hamburger': 'hamburger',
    'hot dog': 'frankfurter',
    'ice cream': 'ice cream',
    'juice': 'orange juice',
    'meatball': 'meatball',
    'milk': 'milk',
    'muffin': 'muffin',
    'mushroom': 'mushroom',
    'pancake': 'pancake',
    'pasta': 'pasta',
    'pizza': 'pizza',
    'popcorn': 'popcorn',
    'rice': 'rice cooked',
    'salad': 'salad',
    'sandwich': 'sandwich',
    'seafood': 'fish',
    'soup': 'soup',
    'sushi': 'sushi',
    'taco': 'taco',
    'tea': 'tea',
    'toast': 'bread toasted',
    'vegetable': 'vegetables mixed',
    'waffle': 'waffle',
  };

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
