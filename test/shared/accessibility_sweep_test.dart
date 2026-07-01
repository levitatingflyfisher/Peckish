import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

/// The fleet's recurring accessibility bug: rigid rows overflow at large
/// text scale on narrow phones. Every top-level screen must survive 320dp
/// at 2× text with zero layout exceptions.
void main() {
  final screens = <String, Widget>{
    'Today': const TodayScreen(),
    'Plan': const PlanScreen(),
    'Recipes': const RecipesScreen(),
    'Groceries': const GroceriesScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} survives 320dp at 2.0 text scale',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: entry.value,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Unmount and pump past drift's keep-alive timer; never close (see
      // the drift widget-test rules in groceries_screen_test.dart).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
