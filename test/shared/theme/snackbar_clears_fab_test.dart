import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';

/// v0.9.1 phone verdict: "the edit popup bar covers the plus". The
/// log-confirmation SnackBar presents in the nav shell's root Scaffold
/// (`app_router.dart`'s `_TabShell`), which has no FAB of its own — so
/// Today's own FAB (`today_screen.dart`) never raises for it, and the
/// default fixed/full-width SnackBar sits right under the + button.
///
/// Hosted through the REAL router (not a hand-built Scaffold nesting) so
/// this reproduces the actual `_TabShell`-wraps-`TodayScreen` topology the
/// phone bug needs — a shallower nesting does not reproduce it.
void main() {
  testWidgets('logging a regular never covers the FAB with its toast',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // A long-ago entry: shows as a one-tap regular, not in today's own
    // list — so the tap logs a fresh line and the toast is unambiguous.
    await DiaryRepository(db).log(DiaryEntry(
      id: 'e-1',
      day: '2020-01-01',
      at: DateTime(2020, 1, 1, 12),
      food: const FoodRef.quick(),
      label: 'Porridge',
      qty: 1,
      unitLabel: 'bowl',
      grams: null,
      macros: const MacroSet(kcal: 320),
      source: EntrySource.tap,
      createdAt: DateTime(2020, 1, 1, 12),
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    // Let the SnackBar's entrance transition finish — a bare pump() catches
    // frame zero of the slide-in, where its rect is still zero-height and
    // any overlap check passes for free.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    // The SnackBar widget's own render box stretches to the full available
    // width regardless of margin (an Align with no widthFactor fills its
    // parent) — the margin only shrinks its rendered CARD, the Material
    // inside. Measuring the outer SnackBar rect would pass for free no
    // matter what margin is configured.
    final cardRect = tester.getRect(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);
    expect(fabRect.overlaps(cardRect), isFalse,
        reason: 'the log toast must clear the FAB band, never cover it');

    // Clear the SnackBar's own auto-dismiss timer before tearing down.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
