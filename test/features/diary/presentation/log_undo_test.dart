import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// VISION.md's law: "forgiveness over prevention applies to data too."
// Logging a regular is one tap and easy to fat-finger; the confirmation
// toast has to be able to take the line back, not just announce it.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<void> seedRegular(WidgetTester tester) => tester.runAsync(() async {
        final at = DateTime.now().subtract(const Duration(days: 3));
        await DiaryRepository(db).log(DiaryEntry(
          id: 'seed',
          day: DiaryEntry.dayOf(at),
          at: at,
          food: const FoodRef.custom('porridge'),
          label: 'Porridge',
          qty: 1,
          unitLabel: 'bowl',
          grams: null,
          macros: const MacroSet(kcal: 320, proteinG: 11),
          source: EntrySource.tap,
          createdAt: at,
        ));
      });

  Widget host() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('logging a regular offers Undo, and Undo takes the line back',
      (tester) async {
    await seedRegular(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Porridge'));
    // Let the SnackBar's entrance transition finish before reading its
    // layout or tapping into it — mid-animation geometry is unstable.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Logged Porridge'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget,
        reason: 'a one-tap log is easy to fat-finger and must be reversible');
    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsOneWidget,
      reason: 'the tap logged the line before Undo is even considered',
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byType(EntryTile), matching: find.text('Porridge')),
      findsNothing,
      reason: 'Undo removes exactly the line the tap just added',
    );
    await unmount(tester);
  });

  testWidgets('Undo does not touch the habit record', (tester) async {
    await seedRegular(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Porridge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // The rail's chip is still there — undoing a log is not un-reaching for
    // the food. The usage record is append-biased by design.
    expect(find.widgetWithText(ActionChip, 'Porridge'), findsOneWidget);
    await unmount(tester);
  });
}
