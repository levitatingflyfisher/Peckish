import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
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
    // v0.10: a search field on top, three honestly-labelled sections below.
    'Foods': const FoodsScreen(),
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

  Widget narrowHost(AppDatabase db, Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: child,
          ),
        ),
      );

  testWidgets('the speed-dial survives 320dp at 2.0 text scale, open',
      (tester) async {
    // The dial is not a screen, so the loop above never reached it — and
    // v0.9's route row was exactly this shape once: several labelled
    // buttons across the narrowest phone. Every route's label pill must
    // still fit and every circle stay tappable at 2× text.
    final db = AppDatabase(NativeDatabase.memory());
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(narrowHost(db, const TodayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    for (final label in ['Find food', 'Quick add', 'Scan', 'Type a code']) {
      expect(find.text(label), findsOneWidget,
          reason: '$label must still be reachable at 2× text');
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the + sheet survives 320dp at 2.0 text scale', (tester) async {
    // Reached through Find food now that the dial holds the other routes
    // (see the case above) — this is the sheet's OWN survival, not the
    // dial's.
    final db = AppDatabase(NativeDatabase.memory());
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(narrowHost(db, const TodayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find food'));
    await tester.pumpAndSettle();

    expect(find.text('Search foods (works offline)'), findsOneWidget,
        reason: 'the sheet is still reachable at 2× text');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
