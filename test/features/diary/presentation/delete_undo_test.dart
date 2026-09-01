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
import 'package:peckish/shared/widgets/undo_host.dart';

// VISION.md's law: "forgiveness over prevention applies to data too". A
// swipe is an easy gesture, so it asks first, naming the line (the fleet
// delete ruling; the operator's own example is this app's food row). Once
// removed, the Undo stays until the person acts: it never times out.
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
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => UndoHost(child: child!),
          home: const TodayScreen(),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a swipe asks first, naming the line; Cancel leaves it alone',
      (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete Oops?'), findsOneWidget,
        reason: 'a swipe is an easy gesture, so it asks first');
    expect(find.widgetWithText(FilledButton, 'Delete line'), findsOneWidget,
        reason: 'the button names the act, never a bare "Delete"');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsOneWidget,
        reason: 'Cancel must leave the line exactly where it was');
    await unmount(tester);
  });

  testWidgets('confirming removes the line and the Undo does not expire',
      (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete line'));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsNothing);
    expect(find.text('Deleted Oops'), findsOneWidget);
    await tester.pump(const Duration(hours: 1));
    expect(find.text('Undo'), findsOneWidget,
        reason: 'an Undo that vanishes while you read it strands you');
    await unmount(tester);
  });

  testWidgets('Undo puts the exact same line back', (tester) async {
    await seedToday(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(EntryTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete line'));
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
