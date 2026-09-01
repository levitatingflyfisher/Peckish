import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Lens audit visual-display-04: the list said "kcal" with no denominator
// while the recipe's own page said per serving. Same words in both places.
void main() {
  testWidgets('the recipe list says kcal per serving', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() => RecipeRepository(db).create(Recipe(
          id: 'r-1',
          title: 'Roast chicken',
          servings: 4,
          declaredPerServing: const MacroSet(kcal: 620),
          createdAt: DateTime(2026, 7, 25),
        )));
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const RecipesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('620 kcal per serving'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
