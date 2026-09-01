import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

import '../support/backup_overrides.dart';

/// Release gate (roadmap item 24): at 360dp × 1.3 text each primary
/// screen's main action is on screen and tappable (scrolling to it is
/// fine), and the same screen survives 320dp × 3.0 without overflowing.
/// Fresh install, the app's own theme, an in-memory database.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<void> Function() pump(WidgetTester tester, Widget screen) => () async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            recipeDraftStoreProvider
                .overrideWithValue(MemoryRecipeDraftStore()),
            spineReadyProvider.overrideWith((ref) async {}),
            ...backupTestOverrides(),
          ],
          child: MaterialApp(theme: AppTheme.light, home: screen),
        ));
        await tester.pumpAndSettle();
      };

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('TodayScreen: the + is reachable', (tester) async {
    await runPrimaryActionSweep(
      tester,
      pumpScreen: pump(tester, const TodayScreen()),
      primaryAction: find.byType(FloatingActionButton),
    );
    await drain(tester);
  });

  testWidgets('PlanScreen: Set the table is reachable', (tester) async {
    await runPrimaryActionSweep(
      tester,
      pumpScreen: pump(tester, const PlanScreen()),
      primaryAction: find.textContaining('Set the table'),
    );
    await drain(tester);
  });

  testWidgets('GroceriesScreen: the add field is reachable', (tester) async {
    await runPrimaryActionSweep(
      tester,
      pumpScreen: pump(tester, const GroceriesScreen()),
      primaryAction: find.byType(TextField),
    );
    await drain(tester);
  });

  testWidgets('RecipesScreen: Add recipe is reachable', (tester) async {
    await runPrimaryActionSweep(
      tester,
      pumpScreen: pump(tester, const RecipesScreen()),
      primaryAction: find.byTooltip('Add recipe'),
    );
    await drain(tester);
  });

  testWidgets('RecipeEditScreen: Save is reachable', (tester) async {
    await runPrimaryActionSweep(
      tester,
      pumpScreen: pump(tester, const RecipeEditScreen()),
      primaryAction: find.widgetWithText(FilledButton, 'Save'),
    );
    await drain(tester);
  });
}
