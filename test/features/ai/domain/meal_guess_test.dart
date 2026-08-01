import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/domain/meal_guess.dart';

// The model is a parser, never a ledger: its output is a DRAFT the user
// reviews. The parser's job is to never crash, never fabricate, and to
// degrade malformed output to something honest.
void main() {
  group('MealGuess.parse', () {
    test('parses a clean JSON answer', () {
      final g = MealGuess.parse('''
{"foods":[
  {"name":"Chipotle bowl, double chicken","grams":650,"kcal":905,
   "protein_g":72,"carb_g":78,"fat_g":32,"confidence":0.7},
  {"name":"Corn chips","grams":40,"kcal":210,"protein_g":3,
   "carb_g":26,"fat_g":11,"confidence":0.5}
]}''');
      expect(g.foods, hasLength(2));
      expect(g.foods.first.name, 'Chipotle bowl, double chicken');
      expect(g.foods.first.grams, 650);
      expect(g.foods.first.macros.kcal, 905);
      expect(g.foods.first.macros.proteinG, 72);
      expect(g.foods.first.confidence, 0.7);
    });

    test('digs the JSON out of prose wrapping (models narrate)', () {
      final g = MealGuess.parse(
          'Sure! Here is my estimate:\n{"foods":[{"name":"Apple","kcal":95,'
          '"confidence":0.9}]}\nHope that helps!');
      expect(g.foods.single.name, 'Apple');
      expect(g.foods.single.macros.kcal, 95);
      expect(g.foods.single.grams, isNull);
    });

    test('missing numbers stay unknown, never zero', () {
      final g = MealGuess.parse(
          '{"foods":[{"name":"Mystery soup","confidence":0.2}]}');
      final f = g.foods.single;
      expect(f.macros.kcal, isNull);
      expect(f.macros.proteinG, isNull);
      expect(f.grams, isNull);
    });

    test('garbage in → empty guess out, no crash', () {
      expect(MealGuess.parse('I could not understand that.').foods, isEmpty);
      expect(MealGuess.parse('').foods, isEmpty);
      expect(MealGuess.parse('{"foods": "nope"}').foods, isEmpty);
    });

    test(
        'entries without a name are dropped; negatives become unknown; '
        'confidence clamps to 0..1 and defaults low', () {
      final g = MealGuess.parse('''
{"foods":[
  {"grams":100,"kcal":200},
  {"name":"Weird yogurt","kcal":-50,"confidence":7},
  {"name":"Toast"}
]}''');
      expect(g.foods, hasLength(2));
      expect(g.foods.first.name, 'Weird yogurt');
      expect(g.foods.first.macros.kcal, isNull,
          reason: 'a negative guess is garbage, and garbage is unknown');
      expect(g.foods.first.confidence, 1.0);
      expect(g.foods.last.confidence, MealGuess.defaultConfidence);
    });

    test('string-typed numbers are tolerated (models do this)', () {
      final g = MealGuess.parse(
          '{"foods":[{"name":"Rice","grams":"180","kcal":"230","confidence":"0.6"}]}');
      expect(g.foods.single.grams, 180);
      expect(g.foods.single.macros.kcal, 230);
      expect(g.foods.single.confidence, 0.6);
    });
  });

  test('the canonical prompt demands JSON-only and offers the exact shape', () {
    final p = MealGuess.promptFor('two eggs and toast');
    expect(p, contains('ONLY a JSON object'));
    expect(p, contains('"foods"'));
    expect(p, contains('two eggs and toast'));
  });
}
