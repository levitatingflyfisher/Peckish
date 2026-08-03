import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// The reported bug, in the user's own words:
//
//   "I often click out of the 'enter the data' screen because I swipe away
//    to see the info on a different app (a pic on my messenger app) then
//    swipe back and the keyboard lowers, moving the window, and I click and
//    miss the window and it closes."
//
// Two things are true at once and only the second is a defect:
//
//  1. The keyboard does NOT come back when Android resumes an app, so
//     viewInsets drops to zero and every sheet that pads by it shrinks.
//     That is the platform behaving correctly, and we cannot fight it —
//     re-showing an IME on resume is exactly the kind of thing that works
//     on one phone and not the next.
//  2. A modal holding work you have typed is DESTROYED by one ambiguous
//     tap, with no confirmation and no recovery. The moving window is
//     merely the commonest way to aim that tap by accident; a fat finger
//     on the scrim loses the same data on a phone that never left the
//     foreground.
//
// So these tests pin (1) as the trigger and fix (2) as the bug.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  const nutella = OffProduct(
    barcode: '3017620422003',
    name: 'Nutella',
    brand: 'Ferrero',
    per100g: MacroSet(kcal: 539),
    servingLabel: '15 g',
    servingGrams: 15,
  );

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

  /// Raise/lower the on-screen keyboard the way the platform does.
  void keyboard(WidgetTester tester, {required bool up}) {
    tester.view.viewInsets =
        up ? const FakeViewPadding(bottom: 600) : FakeViewPadding.zero;
  }

  testWidgets(
      'the trigger: lowering the keyboard moves the sheet out from '
      'under where you were about to tap', (tester) async {
    addTearDown(tester.view.reset);
    keyboard(tester, up: true);

    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showProductSheet(context, nutella),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Where the amount field sits while you are typing into it.
    final aimedAt = tester.getCenter(find.byType(TextField));

    // Swipe away, swipe back: Android does not restore the IME.
    keyboard(tester, up: false);
    await tester.pumpAndSettle();

    final sheetNow = tester.getRect(find.byType(TextField));
    expect(sheetNow.contains(aimedAt), isFalse,
        reason: 'if the field had not moved there would be no bug to fix — '
            'this is the trigger the fix has to survive');
    await unmount(tester);
  });

  testWidgets(
      'a tap that misses the product sheet does not throw the '
      'work away', (tester) async {
    addTearDown(tester.view.reset);
    keyboard(tester, up: true);

    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showProductSheet(context, nutella),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '37');
    await tester.pump();

    keyboard(tester, up: false);
    await tester.pumpAndSettle();

    // The miss: a tap near the top of the screen, well clear of the sheet.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('Log it'), findsOneWidget,
        reason: 'a stray tap must not discard what you typed');
    expect(find.widgetWithText(TextField, '37'), findsOneWidget,
        reason: 'and the amount you entered is still there');
    await unmount(tester);
  });

  testWidgets('a tap that misses Quick add does not throw five fields away',
      (tester) async {
    addTearDown(tester.view.reset);
    keyboard(tester, up: true);

    await tester.pumpWidget(host(const _AddSheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'What was it?').last, 'Leftover chilli');
    await tester.enterText(find.widgetWithText(TextField, 'kcal').last, '620');
    await tester.pump();

    keyboard(tester, up: false);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('Quick add'), findsWidgets,
        reason: 'the dialog holding five typed fields must survive a miss');
    expect(find.widgetWithText(TextField, 'Leftover chilli'), findsOneWidget);
    expect(find.widgetWithText(TextField, '620'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the X closes the product sheet — the way out is visible',
      (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showProductSheet(context, nutella),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sheet-close')));
    await tester.pumpAndSettle();

    expect(find.text('Log it'), findsNothing,
        reason: 'once tapping away stops working there must be something '
            'to tap instead, and it must be visible without scrolling');
    await unmount(tester);
  });

  testWidgets('the + sheet has a visible way out too', (tester) async {
    await tester.pumpWidget(host(const _AddSheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sheet-close')));
    await tester.pumpAndSettle();

    expect(find.text('Scan'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a sheet with nothing typed in it still closes on a tap away',
      (tester) async {
    // The rule is scoped on purpose. Tapping outside is the RIGHT gesture
    // for "never mind" — it only becomes a bug when it destroys work.
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showConfirmDialog(context,
            title: 'Delete this?', message: 'It will be gone.'),
        child: const Text('open'),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('Delete this?'), findsNothing,
        reason: 'a confirm holds nothing you typed — tapping away is how '
            'anyone expects to back out of one');
    await unmount(tester);
  });

  testWidgets('Cancel still closes Quick add — not a trap', (tester) async {
    await tester.pumpWidget(host(const _AddSheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Log it'), findsNothing,
        reason: 'refusing a stray tap must never mean refusing to close');
    expect(find.text('Scan'), findsOneWidget,
        reason: 'Cancel returns to the + sheet, where you would try again');
    await unmount(tester);
  });
}

class _AddSheetHost extends StatelessWidget {
  const _AddSheetHost();

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) => TextButton(
          onPressed: () => showAddSheet(context),
          child: const Text('open'),
        ),
      );
}
