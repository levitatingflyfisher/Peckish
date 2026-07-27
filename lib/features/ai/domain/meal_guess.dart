import 'dart:convert';

import 'package:peckish/features/food/domain/macro_set.dart';

/// One food the model thinks it heard, with its confidence in the guess.
/// A draft line, not a ledger line — nothing here is logged until the user
/// confirms it.
class GuessedFood {
  const GuessedFood({
    required this.name,
    required this.grams,
    required this.macros,
    required this.confidence,
  });

  final String name;
  final double? grams;
  final MacroSet macros;

  /// 0..1 — surfaced at review time so the user knows how hard to squint.
  final double confidence;
}

/// The model's parsed answer to "what did you eat?".
///
/// The model is a PARSER, never a ledger: [parse] never crashes, never
/// fabricates a field, and degrades garbage to an empty guess the UI can
/// state calmly.
class MealGuess {
  const MealGuess(this.foods);

  final List<GuessedFood> foods;

  static const defaultConfidence = 0.3;

  /// The one canonical prompt every backend gets — JSON-only, exact shape,
  /// portions estimated when unspecified.
  static String promptFor(String description) => '''
You are a nutrition parser inside a family food diary. The user describes
what they ate. Respond with ONLY a JSON object, no prose before or after,
in exactly this shape:
{"foods":[{"name":"...","grams":123,"kcal":123,"protein_g":12,"carb_g":12,"fat_g":12,"confidence":0.7}]}
Rules: one object per distinct food; use realistic typical portions for
anything unspecified; omit (or null) any number you cannot estimate rather
than guessing wildly; confidence is 0.0-1.0 for the line as a whole. If
nothing edible is described, answer {"foods":[]}.

The user ate: $description''';

  /// Parses a model answer: digs the first `{...}` block out of any prose
  /// wrapping, tolerates string-typed numbers, drops nameless lines, turns
  /// negative numbers into unknown, clamps confidence into 0..1.
  static MealGuess parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return const MealGuess([]);

    final Object decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      return const MealGuess([]);
    }
    if (decoded is! Map || decoded['foods'] is! List) {
      return const MealGuess([]);
    }

    final foods = <GuessedFood>[];
    for (final item in decoded['foods'] as List) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      foods.add(GuessedFood(
        name: name,
        grams: _positive(item['grams']),
        macros: MacroSet(
          kcal: _positive(item['kcal']),
          proteinG: _positive(item['protein_g']),
          carbG: _positive(item['carb_g']),
          fatG: _positive(item['fat_g']),
        ),
        confidence:
            (_toDouble(item['confidence']) ?? defaultConfidence).clamp(0, 1),
      ));
    }
    return MealGuess(foods);
  }

  /// A negative "estimate" is garbage, and garbage is unknown — never zero,
  /// never a subtraction from the day.
  static double? _positive(Object? v) {
    final d = _toDouble(v);
    return d == null || d < 0 ? null : d;
  }

  static double? _toDouble(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };
}
