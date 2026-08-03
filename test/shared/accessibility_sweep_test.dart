import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/presentation/plan_screen.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

/// The fleet's recurring accessibility bug: rigid rows overflow at large
/// text scale on narrow phones. Every top-level screen must survive 320dp
/// at 2× text with zero layout exceptions.
///
/// Necessary, NOT sufficient — and v0.9 is the proof. This gate passed
/// clean through a macro label sheared to 40% of itself and a day total
/// split into "29" over "00", because both were widgets that CLIP rather
/// than overflow: a `Chip` fixes its own height and forces one line, and
/// wrapped text simply wraps. Nothing throws, so nothing here fires. When
/// a screen carries numbers that must be read exactly, pin those in a
/// layout test of its own (history_layout_test.dart) as well as here.
void main() {
  final screens = <String, Widget>{
    'Today': const TodayScreen(),
    'Plan': const PlanScreen(),
    'Recipes': const RecipesScreen(),
    'Groceries': const GroceriesScreen(),
    // History became a tab in v0.9, and a past day gained a totals card
    // and a regulars rail — both new rigid rows on the narrowest screen.
    'History': const HistoryScreen(today: '2026-08-14'),
    'A past day': const HistoryDayScreen(day: '2026-08-13'),
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

  testWidgets('the + sheet survives 320dp at 2.0 text scale', (tester) async {
    // The sheet is not a screen, so the loop above never reached it — and
    // v0.9's route row is exactly the shape that bites here: several
    // labelled buttons across the narrowest phone. A Wrap is why this
    // passes; a Row would not.
    final db = AppDatabase(NativeDatabase.memory());
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: TodayScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Quick add'), findsOneWidget,
        reason: 'every way in is still reachable at 2× text');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
