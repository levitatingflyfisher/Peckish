import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// The phone-test complaint this screen answers: "there's no good way to view
// common items besides that one horizontal bar." Foods = the regulars,
// manageable, plus My Foods with full CRUD.
// Drift widget-test rules apply (runAsync-seed, UI asserts, unmount).

Widget host(AppDatabase db) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const FoodsScreen()),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

DiaryEntry entry({required String id, String label = 'Oatmeal'}) {
  final when = DateTime(2026, 7, 1, 8);
  return DiaryEntry(
    id: id,
    day: DiaryEntry.dayOf(when),
    at: when,
    food: const FoodRef.quick(),
    label: label,
    qty: 1,
    unitLabel: 'serving',
    grams: null,
    macros: const MacroSet(kcal: 150),
    source: EntrySource.manual,
    createdAt: when,
  );
}

CustomFood food({String id = 'cf-1', String name = 'Cafe Rio salad'}) =>
    CustomFood(
      id: id,
      name: name,
      servingLabel: '1 salad',
      perServing: const MacroSet(kcal: 640, proteinG: 42),
      createdAt: DateTime(2026, 7, 1),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('a logged food shows under Regulars with its use count',
      (tester) async {
    await tester.runAsync(() async {
      await DiaryRepository(db).log(entry(id: 'e-1'));
      await DiaryRepository(db).log(entry(id: 'e-2'));
    });
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    expect(find.text('Regulars'), findsOneWidget);
    expect(find.text('Oatmeal'), findsOneWidget);
    expect(find.textContaining('2×'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hide moves a regular out of the list; Show again returns it',
      (tester) async {
    await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide from rail'));
    await tester.pumpAndSettle();

    // Gone from the live section, present under Hidden.
    expect(find.text('Hidden regulars'), findsOneWidget);
    await tester.tap(find.text('Hidden regulars'));
    await tester.pumpAndSettle();
    expect(find.text('Oatmeal'), findsOneWidget);

    // The hidden tile's menu is the only one left on screen.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show again'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden regulars'), findsNothing);
    expect(find.text('Oatmeal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('My Foods lists customs and Edit rewrites in place',
      (tester) async {
    await tester.runAsync(() => CustomFoodRepository(db).create(food()));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    expect(find.text('My Foods'), findsOneWidget);
    expect(find.text('Cafe Rio salad'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name').last, 'Cafe Rio bowl');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Cafe Rio bowl'), findsOneWidget);
    expect(find.text('Cafe Rio salad'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Delete asks first, then the food is gone', (tester) async {
    await tester.runAsync(() => CustomFoodRepository(db).create(food()));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The confirm dialog is the gate.
    expect(find.textContaining('Delete'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Cafe Rio salad'), findsNothing);
    await unmount(tester);
  });

  testWidgets('an empty screen invites instead of erroring', (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    expect(find.textContaining('Log a few foods'), findsOneWidget);
    await unmount(tester);
  });
}
