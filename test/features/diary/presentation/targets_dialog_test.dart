import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/presentation/targets_dialog.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The easy-goal-setting law: the minimal setup is TWO typed numbers.
// The role defaults (protein = at least, everything else = about) do the
// rest; roles are one dropdown away for anyone who wants them.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget todayHost() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Widget buttonHost() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => showTargetsDialog(context, ref),
                  child: const Text('open targets'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> enterByLabel(
      WidgetTester tester, String label, String value) async {
    await tester.enterText(
        find.widgetWithText(TextField, label).last, value);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog offers four numbers, each with a role', (tester) async {
    await tester.pumpWidget(buttonHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open targets'));
    await tester.pumpAndSettle();

    for (final label in ['Calories', 'Protein g', 'Carbs g', 'Fat g']) {
      expect(find.widgetWithText(TextField, label), findsOneWidget);
    }
    // The defaults are visible before any tap: protein is a floor,
    // the other three are 'About'.
    expect(find.text('At least'), findsOneWidget);
    expect(find.text('About'), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets('two numbers make a day: floor protein, about calories',
      (tester) async {
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();

    // Unset targets → Today invites.
    await tester.tap(find.text('Set daily targets'));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'Calories', '2000');
    await enterByLabel(tester, 'Protein g', '150');
    await save(tester);

    expect(find.text('of 2000 kcal'), findsOneWidget);
    expect(find.textContaining('min 150g'), findsOneWidget,
        reason: 'the protein floor reads as a floor');
    expect(find.text('Set daily targets'), findsNothing,
        reason: 'the invitation retires once targets exist');
    await unmount(tester);
  });

  testWidgets('choosing Under makes the calories line read as a cap',
      (tester) async {
    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set daily targets'));
    await tester.pumpAndSettle();

    await enterByLabel(tester, 'Calories', '1800');
    // The kcal row's role dropdown shows 'About'; switch it to 'Under'.
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Under').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(find.text('of max 1800 kcal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('reopening shows the saved numbers; clearing them clears the day',
      (tester) async {
    await tester.runAsync(() => TargetsRepository(db).set(const DailyTargets(
        values: MacroSet(kcal: 2000, proteinG: 150))));

    await tester.pumpWidget(buttonHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open targets'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2000'), findsOneWidget,
        reason: 'the dialog opens on what is already set');

    await enterByLabel(tester, 'Calories', '');
    await enterByLabel(tester, 'Protein g', '');
    await save(tester);
    await unmount(tester);

    await tester.pumpWidget(todayHost());
    await tester.pumpAndSettle();
    expect(find.text('Set daily targets'), findsOneWidget,
        reason: 'no targets → the invitation returns');
    expect(find.textContaining('of 2000'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Settings has the Daily targets tile and it opens the editor',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily targets'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Calories'), findsOneWidget);
    await unmount(tester);
  });
}
