import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The law under test: every screen you can walk INTO, you can walk BACK
// out of. v0.3 shipped context.go() for Settings and About — go() REPLACES
// the page stack, so Settings had no back arrow and Android's system back
// exited the app (the user force-closed to escape).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget host() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Settings is pushed, not swapped in: back arrow returns home',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget,
        reason: 'the Settings screen should be up');
    expect(find.byType(BackButton), findsOneWidget,
        reason: 'Settings must keep the page it came from underneath');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Logged today'), findsOneWidget,
        reason: 'back from Settings lands on Today');
    await unmount(tester);
  });

  testWidgets('History is a tab, not a corner icon', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The v0.8 phone test: the month view was an app-bar icon beside
    // Settings, where nothing you actually use every day belongs.
    expect(find.widgetWithText(NavigationBar, 'History'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap any day'), findsOneWidget,
        reason: 'the History tab shows the month view');
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'a tab keeps the nav bar — it is not a drill-down');
    await unmount(tester);
  });

  testWidgets('every tab selects itself, the last one included',
      (tester) async {
    // The fifth tab arriving is exactly when a hardcoded clamp bites: an
    // index past the end silently lights up the wrong destination.
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (final (i, label)
        in ['Today', 'Plan', 'Recipes', 'Groceries', 'History'].indexed) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          i,
          reason: '$label must light up its own destination');
    }
    await unmount(tester);
  });

  testWidgets('a day drilled into from History drops the nav bar',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final key = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await tester.scrollUntilVisible(find.byKey(ValueKey('day-$key')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(ValueKey('day-$key')));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget,
        reason: 'one day is a drill-down, and must be poppable');
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'a drill-down is not a tab');
    await unmount(tester);
  });

  testWidgets('About is pushed too: back returns to Settings, not nowhere',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('About Peckish'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('About Peckish'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget,
        reason: 'About must be poppable');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // The list restores its scrolled position, so assert on the app bar.
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget,
        reason: 'back from About lands on Settings');
    await unmount(tester);
  });
}
