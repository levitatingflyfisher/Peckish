import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/shared/theme/app_theme.dart';

import '../../support/backup_overrides.dart';

// Fleet theme ruling: light, dark or follow the phone, at most two taps from
// any primary screen. Settings used to be the only way, and it is reachable
// only from Today.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    late GoRouter router;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
        ...backupTestOverrides(),
      ],
      child: Consumer(builder: (context, ref, _) {
        router = ref.watch(appRouterProvider);
        return MaterialApp.router(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ref.watch(themeModeProvider),
          routerConfig: router,
        );
      }),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final route in ['/', '/plan', '/recipes', '/groceries', '/history']) {
    testWidgets('$route: the theme choice is in the top bar', (tester) async {
      final router = await pumpApp(tester);
      router.go(route);
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.byType(OhThemeToggle)),
          findsOneWidget);
      await unmount(tester);
    });
  }

  testWidgets('two taps from Groceries turn the app dark, and it sticks',
      (tester) async {
    final router = await pumpApp(tester);
    router.go('/groceries');
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget,
        reason: 'a fresh install follows the phone');

    await tester.tap(find.byType(OhThemeToggle));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Dark').last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    await unmount(tester);
  });
}
