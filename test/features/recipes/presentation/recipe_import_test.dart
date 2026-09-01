import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/recipes/import/recipe_fetcher.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Lens audit writing-01 (and ten lenses with it): the import failure printed
// "Import failed: ClientException: Failed to fetch, uri=…" in a timed toast
// after the dialog had already closed, with no busy state and no way back.
// Now the dialog stays up through the fetch, the button says it is busy,
// Cancel works mid-fetch, and a failure is a plain sentence under the link
// the person can still correct.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget host(http.Client client) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          recipeFetcherProvider
              .overrideWithValue(RecipeFetcher(client: client)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const RecipesScreen()),
      );

  Future<void> openPaste(WidgetTester tester, String url) async {
    await tester.tap(find.byTooltip('Add recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste a recipe link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), url);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a failed fetch is a sentence in place, never the exception',
      (tester) async {
    await tester.pumpWidget(host(MockClient(
        (_) async => throw http.ClientException('Failed to fetch'))));
    await tester.pumpAndSettle();
    await openPaste(tester, 'https://example.invalid/soup');

    await tester.runAsync(() async {
      await tester.tap(find.text('Fetch'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'the dialog stays open so the link can be corrected');
    expect(find.text('https://example.invalid/soup'), findsOneWidget);
    expect(find.textContaining('That page didn’t answer'), findsOneWidget);
    expect(find.textContaining('ClientException'), findsNothing);
    expect(find.textContaining('Failed to fetch'), findsNothing);
    expect(find.text('Write it down instead'), findsOneWidget,
        reason: 'the failure offers the other door');
    await unmount(tester);
  });

  testWidgets('the button says it is busy, and Cancel works mid-fetch',
      (tester) async {
    final answer = Completer<http.Response>();
    await tester.pumpWidget(host(MockClient((_) => answer.future)));
    await tester.pumpAndSettle();
    await openPaste(tester, 'https://example.com/soup');

    await tester.tap(find.text('Fetch'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // The page answering later must not open anything.
    await tester.runAsync(() async {
      answer.complete(http.Response(
          '<script type="application/ld+json">{"@type":"Recipe",'
          '"name":"Soup","recipeIngredient":["water"]}</script>',
          200));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Check the import'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a page with no recipe says so in place', (tester) async {
    await tester.pumpWidget(host(
        MockClient((_) async => http.Response('<p>hello</p>', 200))));
    await tester.pumpAndSettle();
    await openPaste(tester, 'https://example.com/blog');

    await tester.runAsync(() async {
      await tester.tap(find.text('Fetch'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Couldn’t find a recipe'), findsOneWidget);
    await unmount(tester);
  });
}
