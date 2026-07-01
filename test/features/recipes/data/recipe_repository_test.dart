import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';

Recipe tacos() => Recipe(
      id: 'r-1',
      title: 'Weeknight Tacos',
      servings: 4,
      sourceUrl: 'https://example.com/tacos',
      instructions: 'Brown the beef.\nWarm the tortillas.',
      createdAt: DateTime(2026, 7, 25),
      ingredients: [
        const RecipeIngredient(
          id: 'ri-1',
          text: '1 lb ground beef',
          food: FoodRef.usda(1),
          grams: 454,
          macros: MacroSet(kcal: 1150, proteinG: 78, carbG: 0, fatG: 90),
        ),
        const RecipeIngredient(
          id: 'ri-2',
          text: '8 corn tortillas',
        ),
      ],
    );

void main() {
  late AppDatabase db;
  late RecipeRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = RecipeRepository(db);
  });

  tearDown(() => db.close());

  test('create → read back keeps ingredients in order, matched or not',
      () async {
    await repo.create(tacos());
    final got = (await repo.byId('r-1'))!;
    expect(got.title, 'Weeknight Tacos');
    expect(got.servings, 4);
    expect(got.ingredients.map((i) => i.text).toList(),
        ['1 lb ground beef', '8 corn tortillas']);
    expect(got.ingredients.first.food?.usdaFdcId, 1);
    expect(got.ingredients.last.food, isNull);
    expect(got.instructions, contains('tortillas'));
  });

  test('computed per-serving macros divide matched ingredients by servings',
      () {
    final r = tacos();
    final per = r.computedPerServing!;
    expect(per.kcal, closeTo(287.5, 0.01));
    expect(per.proteinG, closeTo(19.5, 0.01));
  });

  test('declared (site-published) nutrition wins over computed', () {
    final r = Recipe(
      id: 'r-2',
      title: 'Declared',
      servings: 2,
      createdAt: DateTime(2026, 7, 25),
      declaredPerServing: const MacroSet(kcal: 300),
      ingredients: const [],
    );
    expect(r.perServing!.kcal, 300);
    // and with nothing declared and nothing matched: honest null
    final bare = Recipe(
      id: 'r-3',
      title: 'Bare',
      servings: null,
      createdAt: DateTime(2026, 7, 25),
      ingredients: const [RecipeIngredient(id: 'i', text: 'mystery')],
    );
    expect(bare.perServing, isNull);
  });

  test('update replaces fields and the ingredient list wholesale', () async {
    await repo.create(tacos());
    final edited = tacos().copyWith(
      title: 'Taco Night',
      ingredients: [const RecipeIngredient(id: 'ri-9', text: '1 lime')],
    );
    await repo.update(edited);
    final got = (await repo.byId('r-1'))!;
    expect(got.title, 'Taco Night');
    expect(got.ingredients.single.text, '1 lime');
  });

  test('archive hides, delete removes — CRUD completeness', () async {
    await repo.create(tacos());
    await repo.setArchived('r-1', archived: true);
    expect(await repo.getAll(), isEmpty);
    expect(await repo.getAll(includeArchived: true), hasLength(1));
    await repo.delete('r-1');
    expect(await repo.getAll(includeArchived: true), isEmpty);
  });
}
