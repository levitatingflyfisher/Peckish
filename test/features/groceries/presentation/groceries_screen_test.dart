import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

// Widget-test rules for drift-backed screens (learned the hard way):
// 1. Seed data ONLY via tester.runAsync BEFORE pumpWidget — drift futures
//    complete on Timers and the fake clock only moves on pump().
// 2. Assert on UI STATE, never by awaiting db reads mid-test — cross-zone
//    drift calls can deadlock on drift's internal lock.
// 3. Don't close the db; unmount and pump past drift's stream keep-alive
//    timer instead (closing while anything is live deadlocks).

Widget host(AppDatabase db) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => UndoHost(child: child!),
        home: const GroceriesScreen(),
      ),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('typing into the add field adds a manual item and clears',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Birthday candles');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Exactly one: the list row. The add field cleared itself.
    expect(find.text('Birthday candles'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget); // aisle header
    await unmount(tester);
  });

  testWidgets('tapping an item checks it off (UI state)', (tester) async {
    await tester.runAsync(() => GroceryRepository(db).addManual('Milk'));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    await unmount(tester);
  });

  // Lens audit humane-05 / dmmt-07: grocery deletions were the least
  // protected acts in the app, used one-handed in a shop. A swipe is an
  // easy gesture, so it asks, naming the item; "Clear checked" is a
  // deliberate, worded command that reports its scope and hands it back.

  testWidgets('a swipe asks first, naming the item, then offers Undo',
      (tester) async {
    await tester.runAsync(() => GroceryRepository(db).addManual('Olive oil'));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Olive oil'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove Olive oil?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Olive oil'), findsOneWidget,
        reason: 'Cancel leaves the row where it was');

    await tester.drag(find.text('Olive oil'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove item'));
    await tester.pumpAndSettle();
    expect(find.text('Removed Olive oil'), findsOneWidget);

    await tester.pump(const Duration(hours: 1));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Olive oil'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"Clear checked" is a word, shown only when something is checked',
      (tester) async {
    await tester.runAsync(() => GroceryRepository(db).addManual('Milk'));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    expect(find.text('Clear checked'), findsNothing,
        reason: 'nothing is checked, so there is nothing to clear');
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    expect(find.text('Clear checked').hitTestable(), findsOneWidget,
        reason: 'a visible label, not a glyph whose name only a tooltip has');
    await unmount(tester);
  });

  testWidgets('Clear checked reports how many went and hands them back',
      (tester) async {
    await tester.runAsync(() async {
      final repo = GroceryRepository(db);
      await repo.addManual('Milk');
      await repo.addManual('Eggs');
      await repo.addManual('Bread');
      for (final i in await repo.getAll()) {
        if (i.name != 'Bread') await repo.setChecked(i.id, checked: true);
      }
    });
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear checked'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'a deliberate command does not ask; it can be undone');
    expect(find.text('Milk'), findsNothing);
    expect(find.text('Eggs'), findsNothing);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Cleared 2 checked items'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Eggs'), findsOneWidget);
    await unmount(tester);
  });

  // Lens audit dmmt-08 / finding 3: the empty list quoted only the cute half
  // of "Set the table" and did not say which tab it was on. The act itself
  // is now here, on the same regenerate path and the same week as Plan.
  testWidgets('the empty list offers Set the table from this week\'s plan',
      (tester) async {
    await tester.runAsync(() async {
      await RecipeRepository(db).create(Recipe(
        id: 'r-1',
        title: 'Soup',
        servings: 4,
        createdAt: DateTime(2026, 7, 25),
        ingredients: const [RecipeIngredient(id: 'i-1', text: '1 onion')],
      ));
      await PlanRepository(db).upsert(PlanEntry(
        id: 'p-1',
        day: DiaryEntry.dayOf(DateTime.now()),
        slot: PlanSlot.dinner,
        kind: PlanKind.recipe,
        refId: 'r-1',
      ));
    });
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Set the table from this week’s plan'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('1 onion'), findsOneWidget);
    expect(find.text('Set the table from this week’s plan'), findsNothing,
        reason: 'the empty state goes once the list has something on it');
    await unmount(tester);
  });
}
