import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Day entries showed kcal only (entry_tile.dart:37-50) though P/C/F are
// snapshotted per entry at log time — the totals card already shows all
// four. This is the same information one line down, shared by Today and
// any history day (they render the one EntryTile).
DiaryEntry entry({MacroSet macros = const MacroSet(kcal: 249)}) => DiaryEntry(
      id: 'e-1',
      day: '2026-08-01',
      at: DateTime(2026, 8, 1, 8),
      food: const FoodRef.quick(),
      label: 'Egg burrito',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: macros,
      source: EntrySource.manual,
      createdAt: DateTime(2026, 8, 1, 8),
    );

Widget host(DiaryEntry e) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: EntryTile(entry: e)),
      ),
    );

void main() {
  testWidgets('a full line shows all three macros, rounded', (tester) async {
    await tester.pumpWidget(host(entry(
        macros: const MacroSet(
            kcal: 249, proteinG: 32.4, carbG: 45.1, fatG: 11.9))));
    await tester.pumpAndSettle();

    expect(find.text('P 32.4 · C 45.1 · F 11.9'), findsOneWidget);
  });

  testWidgets('a missing slot reads —, never a fake 0', (tester) async {
    await tester.pumpWidget(
        host(entry(macros: const MacroSet(kcal: 249, proteinG: 32))));
    await tester.pumpAndSettle();

    expect(find.text('P 32 · C — · F —'), findsOneWidget);
  });

  testWidgets('a kcal-only line omits the macro line entirely',
      (tester) async {
    await tester.pumpWidget(host(entry(macros: const MacroSet(kcal: 249))));
    await tester.pumpAndSettle();

    expect(find.textContaining('P —'), findsNothing,
        reason: 'a bare kcal entry says nothing extra, not three unknowns');
  });

  testWidgets('the macro line survives 320dp at 2× text without shearing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: Scaffold(
            body: EntryTile(
              entry: entry(
                  macros: const MacroSet(
                      kcal: 2900, proteinG: 169, carbG: 244, fatG: 122)),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Nothing here throws even if the line is silently sheared — a Chip
    // or a maxLines:1 + ellipsis Text both "fit" while losing characters.
    // Ask the paragraph what it actually laid out: on a SINGLE line, the
    // laid-out width must not be narrower than the text needs. Wrapping
    // to more lines is fine — losing characters is not.
    final finder = find.textContaining('P 169');
    final p = tester.renderObject<RenderParagraph>(finder);
    final wanted = p.getMaxIntrinsicWidth(double.infinity);
    final oneLine = p.getMinIntrinsicHeight(double.infinity);
    final isSingleLine = p.size.height <= oneLine + 1;
    expect(isSingleLine && p.size.width + 0.5 < wanted, isFalse,
        reason: 'the macro line shears: laid out '
            '${p.size.width.toStringAsFixed(1)}px on one line for text '
            'that needs ${wanted.toStringAsFixed(1)}px');
  });
}
