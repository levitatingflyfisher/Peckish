import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// One ingredient line. [text] is the imported/typed line and is ALWAYS kept —
/// matching a line to a food ([food] + [grams] + [macros]) is optional,
/// additive, and reversible. An unmatched line is a first-class citizen, not
/// an error.
class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.text,
    this.food,
    this.grams,
    this.macros,
  });

  final String id;
  final String text;
  final FoodRef? food;
  final double? grams;

  /// Absolute macros for the whole line (already gram-resolved), or null when
  /// the line hasn't been matched.
  final MacroSet? macros;
}

/// A recipe in the box. Nutrition is ambient, never demanded: the site's own
/// declared per-serving values win when present, the computed sum over
/// matched ingredients fills in when the user has matched any, and otherwise
/// the recipe simply has no numbers — which is fine.
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.servings,
    required this.createdAt,
    this.sourceUrl,
    this.instructions = '',
    this.declaredPerServing,
    this.ingredients = const [],
    this.archived = false,
  });

  final String id;
  final String title;
  final double? servings;
  final String? sourceUrl;
  final String instructions;

  /// Per-serving nutrition as published by the source site (schema.org
  /// `nutrition`), when it published any.
  final MacroSet? declaredPerServing;
  final List<RecipeIngredient> ingredients;
  final DateTime createdAt;
  final bool archived;

  /// Sum of matched ingredient lines divided by servings — null unless both
  /// a serving count and at least one matched line exist.
  MacroSet? get computedPerServing {
    final s = servings;
    if (s == null || s <= 0) return null;
    final matched = ingredients.where((i) => i.macros != null).toList();
    if (matched.isEmpty) return null;
    final total =
        matched.fold(const MacroSet(), (MacroSet sum, i) => sum + i.macros!);
    return total * (1 / s);
  }

  MacroSet? get perServing => declaredPerServing ?? computedPerServing;

  Recipe copyWith({
    String? title,
    double? servings,
    String? sourceUrl,
    String? instructions,
    MacroSet? declaredPerServing,
    List<RecipeIngredient>? ingredients,
    bool? archived,
  }) =>
      Recipe(
        id: id,
        title: title ?? this.title,
        servings: servings ?? this.servings,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        instructions: instructions ?? this.instructions,
        declaredPerServing: declaredPerServing ?? this.declaredPerServing,
        ingredients: ingredients ?? this.ingredients,
        createdAt: createdAt,
        archived: archived ?? this.archived,
      );
}
