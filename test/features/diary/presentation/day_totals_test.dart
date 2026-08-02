import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// "I need to report my macros to myself and I can't see my exact breakdown
// for the past days." A dot on a trend line is a shape, not a number. Any
// day you open shows the same four numbers Today shows, against the same
// targets — the past is not a second-class day.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const day = '2026-07-19';

  DiaryEntry entry(String id, MacroSet macros, String label) {
    final at = DateTime.parse('${day}T12:00:00');
    return DiaryEntry(
      id: id,
      day: day,
      at: at,
      food: const FoodRef.quick(),
      label: label,
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      source: EntrySource.manual,
      createdAt: at,
    );
  }

  Widget host() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(
            theme: AppTheme.light, home: const HistoryDayScreen(day: day)),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a past day sums its own macros, every one of them',
      (tester) async {
    await tester.runAsync(() async {
      final repo = DiaryRepository(db);
      await repo.log(entry('e-1',
          const MacroSet(kcal: 500, proteinG: 30, carbG: 40, fatG: 12),
          'Porridge'));
      await repo.log(entry('e-2',
          const MacroSet(kcal: 700, proteinG: 45, carbG: 55, fatG: 20),
          'Chilli'));
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('1200'), findsOneWidget, reason: 'kcal, summed');
    expect(find.textContaining('Protein 75g'), findsOneWidget);
    expect(find.textContaining('Carbs 95g'), findsOneWidget);
    expect(find.textContaining('Fat 32g'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the day is measured against the same targets Today is',
      (tester) async {
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(kcal: 2000, proteinG: 150),
          kcalRole: TargetRole.under));
      await DiaryRepository(db)
          .log(entry('e-1', const MacroSet(kcal: 500, proteinG: 30), 'Toast'));
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('of max 2000 kcal'), findsOneWidget);
    expect(find.textContaining('Protein 30g / min 150g'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an unknown macro stays unknown, never a zero', (tester) async {
    await tester.runAsync(() => DiaryRepository(db)
        .log(entry('e-1', const MacroSet(kcal: 400), 'Just kcal')));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('400'), findsOneWidget);
    expect(find.textContaining('Protein —'), findsOneWidget,
        reason: 'a day logged in kcal alone did not eat zero protein');
    await unmount(tester);
  });

  testWidgets('an empty day says so instead of reporting zeros',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing logged this day'), findsOneWidget);
    await unmount(tester);
  });
}
