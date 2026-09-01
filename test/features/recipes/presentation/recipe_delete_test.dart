import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// The fleet delete ruling: Delete on a recipe's own page is deliberate, so
// it does not ask. The page closes, and the Undo outlives it: the bar sits
// under every screen until the person acts.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('Delete closes the page at once; Undo brings the recipe back',
      (tester) async {
    await tester.runAsync(() => RecipeRepository(db).create(Recipe(
          id: 'r-1',
          title: 'Tacos',
          servings: 4,
          createdAt: DateTime(2026, 7, 25),
          ingredients: const [RecipeIngredient(id: 'i-1', text: '1 onion')],
        )));
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: const RecipesScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tacos'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.text('Delete')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Recipes'), findsOneWidget, reason: 'back on the box');
    expect(find.text('Tacos'), findsNothing);
    expect(find.text('Deleted “Tacos”'), findsOneWidget);

    await tester.pump(const Duration(hours: 1));
    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Tacos'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
