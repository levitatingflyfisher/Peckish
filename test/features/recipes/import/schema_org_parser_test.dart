import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/recipes/import/schema_org_recipe_parser.dart';

String page(String jsonLd) => '''
<!DOCTYPE html><html><head><title>x</title>
<script type="application/ld+json">$jsonLd</script>
</head><body><p>hello</p></body></html>
''';

void main() {
  const parser = SchemaOrgRecipeParser();

  test('parses the plain direct Recipe object', () {
    final r = parser.parse(page('''
      {"@context":"https://schema.org","@type":"Recipe",
       "name":"Weeknight Tacos",
       "recipeYield":"4 servings",
       "recipeIngredient":["1 lb ground beef","8 corn tortillas"],
       "recipeInstructions":[
         {"@type":"HowToStep","text":"Brown the beef."},
         {"@type":"HowToStep","text":"Warm the tortillas."}]}
    '''))!;
    expect(r.title, 'Weeknight Tacos');
    expect(r.servings, 4);
    expect(r.ingredientLines, ['1 lb ground beef', '8 corn tortillas']);
    expect(r.instructions, ['Brown the beef.', 'Warm the tortillas.']);
  });

  test('finds Recipe inside an @graph array (the AllRecipes shape)', () {
    final r = parser.parse(page('''
      {"@context":"https://schema.org","@graph":[
        {"@type":"Organization","name":"Site"},
        {"@type":["Recipe","NewsArticle"],"name":"Graph Soup",
         "recipeYield":[6,"6 servings"],
         "recipeIngredient":["1 onion"],
         "recipeInstructions":"Chop and simmer."}]}
    '''))!;
    expect(r.title, 'Graph Soup');
    expect(r.servings, 6);
    expect(r.instructions, ['Chop and simmer.']);
  });

  test('handles HowToSection nesting', () {
    final r = parser.parse(page('''
      {"@type":"Recipe","name":"Sectioned","recipeIngredient":["x"],
       "recipeInstructions":[
         {"@type":"HowToSection","name":"Dough","itemListElement":[
            {"@type":"HowToStep","text":"Knead."}]},
         {"@type":"HowToSection","name":"Bake","itemListElement":[
            {"@type":"HowToStep","text":"Bake at 400."}]}]}
    '''))!;
    expect(r.instructions, ['Knead.', 'Bake at 400.']);
  });

  test('spec-legal oddities: single HowToStep dict, and a null-text step', () {
    final r = parser.parse(page('''
      {"@type":"Recipe","name":"Odd","recipeIngredient":["x"],
       "recipeInstructions":{"@type":"HowToStep","text":"Only step."}}
    '''))!;
    expect(r.instructions, ['Only step.']);

    final r2 = parser.parse(page('''
      {"@type":"Recipe","name":"Odder","recipeIngredient":["x"],
       "recipeInstructions":[
         {"@type":"HowToStep","text":null},
         {"@type":"HowToStep","text":"Real step."}]}
    '''))!;
    expect(r2.instructions, ['Real step.']);
  });

  test('extracts per-serving nutrition when the site publishes it', () {
    final r = parser.parse(page('''
      {"@type":"Recipe","name":"Nutritious","recipeIngredient":["x"],
       "nutrition":{"@type":"NutritionInformation",
         "calories":"249 calories","proteinContent":"10.9 g",
         "carbohydrateContent":"20 g","fatContent":"13.7 g"}}
    '''))!;
    expect(r.perServing!.kcal, 249);
    expect(r.perServing!.proteinG, 10.9);
    expect(r.perServing!.carbG, 20);
    expect(r.perServing!.fatG, 13.7);
  });

  test('missing nutrition stays null — never fake zeros', () {
    final r = parser.parse(
        page('{"@type":"Recipe","name":"Bare","recipeIngredient":["x"]}'))!;
    expect(r.perServing, isNull);
    expect(r.servings, isNull);
  });

  test('a page with no Recipe entity returns null', () {
    expect(
        parser.parse(page('{"@type":"NewsArticle","headline":"n"}')), isNull);
    expect(parser.parse('<html><body>no json-ld here</body></html>'), isNull);
  });

  test('survives malformed JSON in one block and finds the good block', () {
    const html = '''
      <script type="application/ld+json">{broken json</script>
      <script type="application/ld+json">
        {"@type":"Recipe","name":"Survivor","recipeIngredient":["x"]}
      </script>''';
    expect(parser.parse(html)!.title, 'Survivor');
  });

  test('HTML entities in JSON strings are decoded', () {
    final r = parser.parse(page(
        '{"@type":"Recipe","name":"Mac &amp; Cheese","recipeIngredient":["x"]}'))!;
    expect(r.title, 'Mac & Cheese');
  });
}
