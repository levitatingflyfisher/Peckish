import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/presentation/foods_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// v0.10: /foods becomes ONE searchable surface. Root cause #4: three lists
// (Regulars sorted last-used-first, My Foods A-Z, Saved meals manual order)
// read as "not quite alphabetical" when the sort was never said out loud —
// and an unbounded regulars stream over "hundreds" had no search at all.
// Drift widget-test rules apply (runAsync-seed, UI asserts, unmount).

const searchDebounce = Duration(milliseconds: 300);

Widget host(AppDatabase db, {String? day}) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: FoodsScreen(day: day),
      ),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(searchDebounce);
  await tester.pumpAndSettle();
}

DiaryEntry entry({required String id, String label = 'Oatmeal', DateTime? at}) {
  final when = at ?? DateTime(2026, 7, 1, 8);
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

Future<void> seedUsda(AppDatabase db,
    {int fdcId = 1, String name = 'Egg burrito', double kcal = 249}) async {
  await db.into(db.usdaFoods).insert(UsdaFoodsCompanion.insert(
        fdcId: Value(fdcId),
        source: 'sr',
        name: name,
        nameNorm: name.toLowerCase(),
        kcal: Value(kcal),
      ));
  await db.into(db.usdaPortions).insert(
      UsdaPortionsCompanion.insert(fdcId: fdcId, label: '1 wrap', grams: 226));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  group('idle: three honestly-labelled sections', () {
    testWidgets('a logged food shows under Regulars, sort said out loud',
        (tester) async {
      await tester.runAsync(() async {
        await DiaryRepository(db).log(entry(id: 'e-1'));
        await DiaryRepository(db).log(entry(id: 'e-2'));
      });
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      expect(find.text('Regulars, by last use'), findsOneWidget);
      expect(find.text('Oatmeal'), findsOneWidget);
      expect(find.textContaining('2×'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('hide moves a regular out; Show again returns it',
        (tester) async {
      await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide from rail'));
      await tester.pumpAndSettle();

      expect(find.text('Hidden regulars'), findsOneWidget);
      await tester.tap(find.text('Hidden regulars'));
      await tester.pumpAndSettle();
      expect(find.text('Oatmeal'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show again'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden regulars'), findsNothing);
      expect(find.text('Oatmeal'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('My Foods lists customs A to Z and Edit rewrites in place',
        (tester) async {
      await tester.runAsync(() => CustomFoodRepository(db).create(food()));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      expect(find.text('My Foods, A to Z'), findsOneWidget);
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

    testWidgets('Delete is deliberate: gone at once, with a lasting Undo',
        (tester) async {
      await tester.runAsync(() => CustomFoodRepository(db).create(food()));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Delete'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'choosing Delete from the menu is already the decision');
      expect(find.text('Cafe Rio salad'), findsNothing);
      expect(find.text('Deleted Cafe Rio salad'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Cafe Rio salad'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Saved meals show under their own honest header',
        (tester) async {
      await tester.runAsync(() => SavedMealRepository(db).create(SavedMeal(
            id: 'm-1',
            name: 'Breakfast',
            position: 0,
            createdAt: DateTime(2026, 7, 1),
            items: const [
              SavedMealItem(
                id: 'i-1',
                food: FoodRef.quick(),
                label: 'Toast',
                qty: 1,
                unitLabel: 'slice',
                grams: null,
                macros: MacroSet(kcal: 90),
              ),
            ],
          )));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      expect(find.text('Saved meals'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Show all expands the capped regulars list', (tester) async {
      // Tall enough that the capped list (~30 rows) needs no scroll to
      // find "Show all" — this test is about the cap, not the finder.
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        for (var i = 0; i < 35; i++) {
          await DiaryRepository(db).log(entry(
            id: 'e-$i',
            label: 'Food $i',
            at: DateTime(2026, 7, 1).add(Duration(minutes: i)),
          ));
        }
      });
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      // The freshest 30 are on screen; the oldest (Food 0) is not, and
      // there's a way to see it.
      expect(find.text('Food 34'), findsOneWidget);
      expect(find.text('Food 0'), findsNothing);
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('Food 0'), findsOneWidget,
          reason: 'Show all lifts the cap entirely');
      await unmount(tester);
    });

    testWidgets("capping the visible list never truncates Hidden",
        (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        for (var i = 0; i < 32; i++) {
          await DiaryRepository(db).log(entry(
            id: 'e-$i',
            label: 'Food $i',
            at: DateTime(2026, 7, 1).add(Duration(minutes: i)),
          ));
        }
        // Hide two of the OLDEST — outside the ~30 cap on the visible list.
        await FoodUsageRepository(db)
            .setHidden('q:food 0', hidden: true);
        await FoodUsageRepository(db)
            .setHidden('q:food 1', hidden: true);
      });
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hidden regulars'));
      await tester.pumpAndSettle();
      expect(find.text('Food 0'), findsOneWidget);
      expect(find.text('Food 1'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an empty screen invites instead of erroring', (tester) async {
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      expect(find.textContaining('Log a few foods'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('search: one list over all four sources', () {
    testWidgets('finds a regular by name', (tester) async {
      await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      await search(tester, 'oat');
      expect(find.text('Oatmeal'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('finds a My Foods custom by name', (tester) async {
      await tester.runAsync(() => CustomFoodRepository(db).create(food()));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      await search(tester, 'cafe');
      expect(find.text('Cafe Rio salad'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('finds a saved meal by name', (tester) async {
      await tester.runAsync(() => SavedMealRepository(db).create(SavedMeal(
            id: 'm-1',
            name: 'Breakfast burrito',
            position: 0,
            createdAt: DateTime(2026, 7, 1),
            items: const [
              SavedMealItem(
                id: 'i-1',
                food: FoodRef.quick(),
                label: 'Toast',
                qty: 1,
                unitLabel: 'slice',
                grams: null,
                macros: MacroSet(kcal: 90),
              ),
            ],
          )));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      await search(tester, 'burrito');
      expect(find.text('Breakfast burrito'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('finds a USDA spine food, seeded directly (no real import)',
        (tester) async {
      await tester.runAsync(() => seedUsda(db));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      await search(tester, 'burrito');
      expect(find.text('Egg burrito'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('clearing the query returns to the sectioned idle view',
        (tester) async {
      await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
      await tester.pumpWidget(host(db));
      await tester.pumpAndSettle();
      await search(tester, 'oat');
      expect(find.text('Regulars, by last use'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.text('Regulars, by last use'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('every tap carries the day it was opened on', () {
    String yesterday() {
      final now = DateTime.now();
      return DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - 1));
    }

    testWidgets('tapping a regular in search logs to the carried day',
        (tester) async {
      await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
      final day = yesterday();
      await tester.pumpWidget(host(db, day: day));
      await tester.pumpAndSettle();
      await search(tester, 'oat');

      await tester.tap(find.text('Oatmeal').last);
      await tester.pumpAndSettle();

      final logged =
          await tester.runAsync(() => DiaryRepository(db).entriesForDay(day))
              as List<DiaryEntry>;
      expect(logged.map((e) => e.label), contains('Oatmeal'));
      await unmount(tester);
    });

    testWidgets('tapping an idle regular logs to the carried day',
        (tester) async {
      await tester.runAsync(() => DiaryRepository(db).log(entry(id: 'e-1')));
      final day = yesterday();
      await tester.pumpWidget(host(db, day: day));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Oatmeal').first);
      await tester.pumpAndSettle();

      final logged =
          await tester.runAsync(() => DiaryRepository(db).entriesForDay(day))
              as List<DiaryEntry>;
      expect(logged.map((e) => e.label), contains('Oatmeal'));
      await unmount(tester);
    });
  });
}
