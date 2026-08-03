import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
// "There are some minor display/scrolling issues when moving between the
// historical bits" and "it's not obvious the calendar arrows for moving
// between months are at the top of the page."
//
// Both are one fault: the month control scrolled away with the content it
// controls, so by the time you reached the calendar the way to change
// months was off-screen. Plus the fleet's recurring accessibility shape —
// rigid rows at large text scale on a narrow phone.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const today = '2026-08-14';
  const day = '2026-08-13';

  DiaryEntry entry(String id, String d, MacroSet macros) {
    final at = DateTime.parse('${d}T12:00:00');
    return DiaryEntry(
      id: id,
      day: d,
      at: at,
      food: const FoodRef.quick(),
      label: 'Meal $id',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      source: EntrySource.manual,
      createdAt: at,
    );
  }

  Widget host(Widget home) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// A narrow phone at a large accessibility text scale — the size at which
  /// the fleet's layout faults actually show.
  void narrowAndLarge(WidgetTester tester, {double scale = 2.0}) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('the month control is outside the scroll view entirely',
      (tester) async {
    await tester.runAsync(() => DiaryRepository(db)
        .log(entry('e-1', today, const MacroSet(kcal: 1900))));
    await tester.pumpWidget(host(const HistoryScreen(today: today)));
    await tester.pumpAndSettle();

    // Structural, not positional: a positional check passes for free
    // whenever the content happens to fit. The control that changes the
    // month simply must not live in the thing it scrolls.
    expect(
        find.descendant(
            of: find.byType(Scrollable),
            matching: find.byKey(const ValueKey('month-prev'))),
        findsNothing,
        reason: 'the way to change months must not scroll off with the '
            'month — you only reach for it once you are down at the '
            'calendar');
    expect(
        find.descendant(
            of: find.byType(Scrollable), matching: find.text('August 2026')),
        findsNothing,
        reason: 'and the month it applies to stays named beside it');
    await unmount(tester);
  });

  testWidgets('the pinned control still works, and still stops at now',
      (tester) async {
    await tester.pumpWidget(host(const HistoryScreen(today: today)));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('month-next')))
            .onPressed,
        isNull,
        reason: 'there is no forward from the month you are living in');

    await tester.tap(find.byKey(const ValueKey('month-prev')));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('month-next')));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the kcal figure is one number, never split across lines',
      (tester) async {
    narrowAndLarge(tester);
    await tester.runAsync(() => DiaryRepository(db)
        .log(entry('e-1', day, const MacroSet(kcal: 2900, proteinG: 169))));

    await tester.pumpWidget(host(const HistoryDayScreen(day: day)));
    await tester.pumpAndSettle();

    // "2900" wrapping to "29 / 00" is not a big number, it is two small
    // wrong ones.
    final text = tester.widget<Text>(find.text('2900'));
    expect(text.maxLines, 1);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('macro chips keep their whole label at 2x text', (tester) async {
    narrowAndLarge(tester);
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(kcal: 2200, proteinG: 150, carbG: 220, fatG: 70)));
      await DiaryRepository(db).log(entry('e-1', day,
          const MacroSet(kcal: 2900, proteinG: 169, carbG: 244, fatG: 122)));
    });

    await tester.pumpWidget(host(const HistoryDayScreen(day: day)));
    await tester.pumpAndSettle();

    // A Chip clips its own label, so a chip that "fits" its parent can
    // still be showing "Protein 169g / min 15". Ask the paragraph what it
    // actually laid out: a SINGLE line narrower than the text needs is a
    // sheared label. Wrapping to two lines is fine — losing characters is
    // not.
    for (final label in ['Protein', 'Carbs', 'Fat']) {
      final finder = find.textContaining(label);
      final p = tester.renderObject<RenderParagraph>(finder);
      final wanted = p.getMaxIntrinsicWidth(double.infinity);
      final oneLine = p.getMinIntrinsicHeight(double.infinity);
      final isSingleLine = p.size.height <= oneLine + 1;
      expect(isSingleLine && p.size.width + 0.5 < wanted, isFalse,
          reason: '$label pill shears its label: laid out '
              '${p.size.width.toStringAsFixed(1)}px on one line for text '
              'that needs ${wanted.toStringAsFixed(1)}px');

      // And having wrapped, the label must actually FIT its container —
      // otherwise the clipping simply moves from the right edge to the
      // bottom one.
      final pill = tester.getRect(
          find.ancestor(of: finder, matching: find.byType(Container)).first);
      final textRect = tester.getRect(finder);
      expect(textRect.bottom, lessThanOrEqualTo(pill.bottom + 0.5),
          reason: '$label label is cut off at the bottom of its pill');
    }
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('the kcal figure stays the biggest thing on the card',
      (tester) async {
    narrowAndLarge(tester);
    await tester.runAsync(() async {
      await TargetsRepository(db).set(const DailyTargets(
          values: MacroSet(kcal: 2200), kcalRole: TargetRole.under));
      await DiaryRepository(db)
          .log(entry('e-1', day, const MacroSet(kcal: 2900)));
    });

    await tester.pumpWidget(host(const HistoryDayScreen(day: day)));
    await tester.pumpAndSettle();

    // Squeezing the hero number into whatever the caption left over made
    // it SMALLER than its own caption — technically unwrapped, visually
    // backwards.
    final number = tester.getRect(find.text('2900'));
    final caption = tester.getRect(find.textContaining('of max 2200 kcal'));
    expect(number.height, greaterThan(caption.height),
        reason: 'the day total should not be dwarfed by its own label');
    await unmount(tester);
  });
}
