import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

import '../../support/backup_overrides.dart';

// Tablet and browser (roadmap item 20/30): every screen caps its content at
// OhPage's phone width and centres it, instead of the old app-wide 760 px
// box that also squeezed the bars, dialogs and sheets.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const routes = [
    '/',
    '/plan',
    '/recipes',
    '/groceries',
    '/history',
    '/history/2026-08-13',
    '/settings',
    '/about',
    '/foods',
    '/sync',
    '/privacy',
    '/barcode-db',
  ];

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final route in routes) {
    testWidgets('$route caps its content at 1024dp', (tester) async {
      wide(tester);
      late GoRouter router;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          recipeDraftStoreProvider.overrideWithValue(MemoryRecipeDraftStore()),
          spineReadyProvider.overrideWith((ref) async {}),
          ...backupTestOverrides(),
        ],
        child: Consumer(builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(
              theme: AppTheme.light, routerConfig: router);
        }),
      ));
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.byType(OhPage), findsWidgets,
          reason: '$route should sit in an OhPage');
      final body = tester.getRect(find.byType(OhPage).last);
      expect(body.width, 1024, reason: 'the page spans the window');
      final bars = tester.getRect(find.byType(AppBar).last);
      expect(bars.width, 1024,
          reason: 'bars span the window; only the content is capped');
      await unmount(tester);
    });
  }

  testWidgets('recipe pages cap their content too', (tester) async {
    wide(tester);
    await tester.runAsync(() => RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Tacos',
        servings: 4,
        createdAt: DateTime(2026, 7, 25))));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        recipeDraftStoreProvider.overrideWithValue(MemoryRecipeDraftStore()),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const RecipeDetailScreen(recipeId: 'r-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OhPage), findsOneWidget);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        recipeDraftStoreProvider.overrideWithValue(MemoryRecipeDraftStore()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const RecipeEditScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OhPage), findsOneWidget);
    await unmount(tester);
  });
}
