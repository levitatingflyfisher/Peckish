import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Lens audit humane-01: the recipe editor, the longest form in the app,
// discarded everything on the system back gesture. What is typed now stays
// as a draft: leave by any route, come back, and it is there.
void main() {
  late AppDatabase db;
  late RecipeDraftStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = MemoryRecipeDraftStore();
  });

  Widget host() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          recipeDraftStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const RecipeEditScreen())),
                  child: const Text('Write one down'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Write one down'));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('back keeps what was typed; coming back picks it up',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Sunday roast chicken');
    await tester.enterText(
        find.widgetWithText(TextField, 'Ingredients, one per line'),
        '1 chicken\n2 lemons');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Write one down'), findsOneWidget, reason: 'left it');

    await open(tester);
    expect(find.text('Sunday roast chicken'), findsOneWidget);
    expect(find.text('1 chicken\n2 lemons'), findsOneWidget);
    expect(find.text('Picked up where you left off.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the draft survives a restart', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Soup');
    await unmount(tester);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.text('Soup'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Start over empties the form and forgets the draft',
      (tester) async {
    await store.write('new', const RecipeDraft(title: 'Soup'));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(find.text('Soup'), findsNothing);
    expect(store.read('new'), isNull);
    await unmount(tester);
  });

  testWidgets('saving uses the draft up', (tester) async {
    await store.write('new', const RecipeDraft(title: 'Soup'));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(store.read('new'), isNull);
    await unmount(tester);
  });

  testWidgets('Erase all data takes the drafts with it', (tester) async {
    await store.write('new', const RecipeDraft(title: 'Soup'));
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        recipeDraftStoreProvider.overrideWithValue(store),
      ],
      child: Consumer(builder: (context, ref, _) {
        captured = ref;
        return const SizedBox();
      }),
    ));
    await tester.runAsync(() => eraseAllData(captured));
    expect(store.read('new'), isNull);
    await unmount(tester);
  });

  // Lens audit humane-10 / doet-06: Save did nothing at all on an empty
  // title. It is now disabled until there is one, and says why.
  testWidgets('Save waits for a title and says so', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await open(tester);
    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save().onPressed, isNull);
    expect(find.text('Give the recipe a title to save it.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Soup');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    expect(find.text('Give the recipe a title to save it.'), findsNothing);
    await unmount(tester);
  });
}
