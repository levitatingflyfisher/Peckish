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
