import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The laws under test: the model's answer is a DRAFT the user can prune,
// nothing is logged until they confirm, and what lands carries ai
// provenance.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const config = AiConfig(
    backend: AiBackend.anthropic,
    anthropicKey: 'sk-ant-test',
  );

  MockClient twoFoods() => MockClient((_) async => http.Response(
        jsonEncode({
          'content': [
            {
              'type': 'text',
              'text': '{"foods":['
                  '{"name":"Chipotle bowl","grams":650,"kcal":905,'
                  '"confidence":0.7},'
                  '{"name":"Corn chips","grams":40,"kcal":210,'
                  '"confidence":0.3}]}'
            }
          ]
        }),
        200,
      ));

  Widget host(http.Client client) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          aiConfigProvider.overrideWith((ref) async => config),
          guessHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> openSheet(WidgetTester tester) async {
    final context = tester.element(find.byType(TodayScreen));
    showGuessSheet(context);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('describe → guess → prune a row → log the rest onto Today',
      (tester) async {
    await tester.pumpWidget(host(twoFoods()));
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.enterText(
        find.byType(TextField), 'chipotle bowl and some chips');
    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();

    // The draft: both foods with honest confidence labels (0.7 reads as
    // confident, 0.3 as a wild guess).
    expect(find.text('Chipotle bowl'), findsOneWidget);
    expect(find.text('Corn chips'), findsOneWidget);
    expect(find.textContaining('confident'), findsOneWidget);
    expect(find.textContaining('wild guess'), findsOneWidget);

    // Prune the chips; log the rest.
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(find.text('Corn chips'), findsNothing);

    await tester.tap(find.textContaining('Log 1 entr'));
    await tester.pumpAndSettle();

    // Sheet closed; the bowl is on Today (ledger row + recents chip).
    expect(find.text('Chipotle bowl'), findsWidgets);
    expect(find.textContaining('905 kcal'), findsOneWidget);
    expect(find.text('Corn chips'), findsNothing,
        reason: 'a pruned draft line must never reach the ledger');
    await unmount(tester);
  });

  testWidgets('a guess opened for a past day lands on THAT day',
      (tester) async {
    final now = DateTime.now();
    final day = DiaryEntry.dayOf(DateTime(now.year, now.month, now.day - 1));

    await tester.pumpWidget(host(twoFoods()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TodayScreen));
    showGuessSheet(context, day: day);
    await tester.pumpAndSettle();

    expect(find.textContaining('Adding to'), findsOneWidget,
        reason: 'prose about a past meal must say which day it feeds');

    await tester.enterText(find.byType(TextField), 'chipotle bowl');
    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Log 2 entr'));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(EntryTile), matching: find.text('Chipotle bowl')),
        findsNothing,
        reason: "yesterday's guess must not appear as one of today's lines");
    await unmount(tester);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child:
          MaterialApp(theme: AppTheme.light, home: HistoryDayScreen(day: day)),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(EntryTile), matching: find.text('Chipotle bowl')),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an unparseable answer is a calm state with a retry path',
      (tester) async {
    final garbage = MockClient((_) async => http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'I do not know what that is.'}
          ]
        }),
        200));
    await tester.pumpWidget(host(garbage));
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't make anything"), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });
}
