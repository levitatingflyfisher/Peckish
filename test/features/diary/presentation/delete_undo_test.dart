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

// VISION.md's law: "forgiveness over prevention applies to data too" — a
// diary entry used to die by unconfirmed swipe hard-delete. Swipe now asks,
// and once removed the toast can put the line straight back.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<void> seedToday(WidgetTester tester) => tester.runAsync(() async {
        final today = DiaryEntry.dayOf(DateTime.now());
        await DiaryRepository(db).log(DiaryEntry(
          id: 'e-1',
          day: today,
          at: DateTime.now(),
          food: const FoodRef.quick(),
          label: 'Oops',
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: const MacroSet(kcal: 249, proteinG: 10.9),
          source: EntrySource.manual,
          createdAt: DateTime.now(),
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

  testWidgets('a swipe asks first — Cancel leaves the line alone',
      (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete Oops?'), findsOneWidget,
        reason: 'the user explicitly asked for a delete confirmation');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsOneWidget,
        reason: 'Cancel must leave the line exactly where it was');
    await unmount(tester);
  });

  testWidgets('confirming removes the line and offers Undo', (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsNothing);
    expect(find.text('Removed Oops'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Undo puts the exact same line back', (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsOneWidget,
        reason: 'Undo re-seats the exact line that was removed');
    expect(
      find.descendant(of: find.byType(EntryTile), matching: find.text('Oops')),
      findsOneWidget,
      reason: 'the ledger row is back, not just the regulars rail chip',
    );
    await unmount(tester);
  });
}
