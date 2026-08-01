import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/diary/presentation/history_screen.dart';
import 'package:peckish/features/diary/presentation/speed_dial_fab.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Root cause #3: "add options live at the TOP of the + sheet, i.e. the far
// end of the reach." The dial puts every way in inside the thumb zone,
// bottom-right, nearest-first by frequency — and RESOLVES the v0.3/#184
// compromise (routes above regulars) instead of fighting it: with the
// routes on the dial, the sheet becomes pure find-and-relog.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Widget host(Widget home, {List<Override> extra = const []}) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
          ...extra,
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  Widget routerHost() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('closed by default: no routes visible until + is tapped',
      (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();

    for (final label in ['Find food', 'Quick add', 'Scan', 'Type a code']) {
      expect(find.text(label), findsNothing);
    }
    await unmount(tester);
  });

  testWidgets('+ expands the dial: every route lands in reach',
      (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    for (final label in ['Find food', 'Quick add', 'Scan', 'Type a code']) {
      expect(find.text(label), findsOneWidget, reason: '$label must be reachable');
    }
    await unmount(tester);
  });

  testWidgets('Guess it stays hidden without a ready brain', (tester) async {
    // `flutter test` reports TargetPlatform.android by default, so the
    // plate-scan rung alone would make aiReady true unless silenced —
    // force both halves of the gate off, the same shape
    // plate_flow_test.dart's "unsupported platform" case uses.
    await tester.pumpWidget(host(
      const TodayScreen(),
      extra: [plateScannerProvider.overrideWithValue(null)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Guess it'), findsNothing,
        reason: 'gated the same as add_sheet.dart used to gate it');
    await unmount(tester);
  });

  testWidgets('Guess it appears once a brain is configured', (tester) async {
    await tester.pumpWidget(host(
      const TodayScreen(),
      extra: [
        plateScannerProvider.overrideWithValue(null),
        aiConfigProvider.overrideWith((ref) async =>
            const AiConfig(backend: AiBackend.anthropic, anthropicKey: 'sk-x')),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Guess it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the visible × actually closes the dial', (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Find food'), findsOneWidget);

    // The compact '+' sits BEHIND the dial route's own barrier once open —
    // this is the button that actually looks like a close affordance and
    // must be the one that works.
    await tester.tap(find.byKey(const ValueKey('dial-close')));
    await tester.pumpAndSettle();
    expect(find.text('Find food'), findsNothing);
    await unmount(tester);
  });

  testWidgets('tapping the scrim collapses the dial — no typed input to lose',
      (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Find food'), findsOneWidget);

    // A corner of the screen the dial itself does not occupy.
    await tester.tapAt(const Offset(20, 100));
    await tester.pumpAndSettle();

    expect(find.text('Find food'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Find food opens the add sheet, day-aware', (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find food'));
    await tester.pumpAndSettle();

    expect(find.text('Search foods — works offline'), findsOneWidget);
    expect(find.textContaining('Adding to'), findsNothing,
        reason: 'Today names no day');
    await unmount(tester);
  });

  testWidgets("Find food on a past day says which day it's feeding",
      (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final day = '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(host(HistoryDayScreen(day: day)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find food'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Adding to'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Quick add opens directly — no sheet underneath', (tester) async {
    await tester.pumpWidget(host(const TodayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'What was it?'), findsOneWidget);
    expect(find.text('Search foods — works offline'), findsNothing,
        reason: 'the sheet resolved v0.3/#184 by not existing here at all');
    await unmount(tester);
  });

  testWidgets('Scan carries the day it was opened from', (tester) async {
    await tester.pumpWidget(routerHost());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'History'));
    await tester.pumpAndSettle();

    // A day with no entries is still drillable.
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    final cell = find.byKey(ValueKey('day-$key'));
    if (cell.evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('month-prev')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(ValueKey('day-$key')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('day-$key')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan a barcode'), findsOneWidget,
        reason: 'the scan screen opened');
    await unmount(tester);
  });

  testWidgets('Type a code opens the scan screen with the keyboard already up',
      (tester) async {
    await tester.pumpWidget(routerHost());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type a code'));
    await tester.pumpAndSettle();

    expect(find.text('Scan a barcode'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
    await unmount(tester);
  });

  test('scanPathForDay carries the day and the typing flag', () {
    expect(scanPathForDay(null), '/scan');
    expect(scanPathForDay('2026-07-30'), '/scan?day=2026-07-30');
    expect(scanPathForDay(null, typing: true), '/scan?type=1');
    expect(scanPathForDay('2026-07-30', typing: true),
        '/scan?day=2026-07-30&type=1');
  });
}
