import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// See groceries_screen_test.dart for the three drift widget-test rules
// (runAsync-seed before pump, UI-state assertions only, unmount not close).

Widget host(AppDatabase db) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

DiaryEntry entry(
        {required String id,
        required String day,
        String label = 'Egg burrito'}) =>
    DiaryEntry(
      id: id,
      day: day,
      at: DateTime(2020, 1, 1, 12),
      food: const FoodRef.quick(),
      label: label,
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: const MacroSet(kcal: 249, proteinG: 10.9),
      source: EntrySource.manual,
      createdAt: DateTime(2020, 1, 1, 12),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('an empty day shows welcoming zero totals, not an error',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets); // kcal total
    expect(find.textContaining('Nothing yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('THE one-tap: tapping a recent logs it onto today (UI state)',
      (tester) async {
    // A long-ago entry: shows in recents, not in today's list.
    await tester.runAsync(
        () => DiaryRepository(db).log(entry(id: 'e-1', day: '2020-01-01')));

    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    // Only the recents chip carries the label before the tap…
    expect(find.text('Egg burrito'), findsOneWidget);
    expect(find.text('249 kcal'), findsNothing);

    await tester.tap(find.text('Egg burrito'));
    await tester.pumpAndSettle();

    // …after it, today's list shows the logged copy with its kcal.
    expect(find.text('Egg burrito'), findsNWidgets(2));
    expect(find.text('249 kcal'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hiding a regular elsewhere clears its chip live',
      (tester) async {
    await tester.runAsync(
        () => DiaryRepository(db).log(entry(id: 'e-1', day: '2020-01-01')));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    expect(find.text('Egg burrito'), findsOneWidget);

    // The Foods screen (or anything) hides it; the rail must react without
    // a diary change.
    await tester.runAsync(
        () => FoodUsageRepository(db).setHidden('q:egg burrito', hidden: true));
    await tester.pumpAndSettle();
    expect(find.text('Egg burrito'), findsNothing);
    await unmount(tester);
  });

  testWidgets("today's entries can be swiped away", (tester) async {
    final today = DiaryEntry.dayOf(DateTime.now());
    await tester.runAsync(() =>
        DiaryRepository(db).log(entry(id: 'e-1', day: today, label: 'Oops')));

    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();
    expect(find.text('249 kcal'), findsOneWidget);

    // The label appears as recents chip + list row; swipe the LIST row (the
    // one showing kcal — it sits inside the Dismissible).
    await tester.drag(find.text('249 kcal'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('249 kcal'), findsNothing);
    await unmount(tester);
  });
}
