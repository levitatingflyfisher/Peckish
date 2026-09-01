import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Lens audit mind-in-mind-10 / dmmt-01: the trend chart's scale labels were
// a hardcoded fontSize 9, painted on a canvas that ignores the text scale,
// so the one text a large-type reader most needs never grew. They now use
// the theme's labelSmall and the reader's text scale, and the chart's left
// gutter widens to fit them.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const today = '2026-08-14';

  DiaryEntry entry(String id, String d, double kcal) {
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
      macros: MacroSet(kcal: kcal),
      source: EntrySource.manual,
      createdAt: at,
    );
  }

  testWidgets('scale labels use labelSmall at the reader\'s text scale',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      await DiaryRepository(db).log(entry('a', '2026-08-12', 2400));
      await DiaryRepository(db).log(entry('b', '2026-08-13', 1800));
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        spineReadyProvider.overrideWith((ref) async {}),
      ],
      child: MaterialApp(
          theme: AppTheme.light, home: const HistoryScreen(today: today)),
    ));
    await tester.pumpAndSettle();

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .where((p) => p.runtimeType.toString() == '_TrendPainter')
        .toList();
    expect(painters, hasLength(1), reason: 'the trend chart should be up');
    final dynamic painter = painters.single;
    final TextStyle style = painter.labelStyle;
    expect(style.fontSize, AppTheme.light.textTheme.labelSmall!.fontSize,
        reason: 'no literal font size on the chart');
    final TextScaler scaler = painter.textScaler;
    expect(scaler.scale(10), 20, reason: 'labels follow the text scale');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
