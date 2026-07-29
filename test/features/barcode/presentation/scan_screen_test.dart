import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/presentation/barcode_sketch.dart';
import 'package:peckish/features/barcode/presentation/scan_mode_store.dart';
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// On this test platform (desktop VM) there is no camera, so the screen runs
// in its universal shape: manual digit entry. The laws under test:
// a bad code costs zero network, not-found is a calm state, and a hit opens
// the confirm sheet.
void main() {
  late AppDatabase db;
  var requests = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = 0;
  });

  OffClient client({int status = 200, String? body}) =>
      OffClient(client: MockClient((request) async {
        requests++;
        return http.Response(
          body ??
              jsonEncode({
                'code': '3017620422003',
                'status': 'success',
                'product': {
                  'product_name': 'Nutella',
                  'brands': 'Ferrero',
                  'nutriments': {'energy-kcal_100g': 539},
                },
              }),
          status,
        );
      }));

  // camera:true forces the camera layout on this camera-less VM; the
  // ScannerView it mounts builds to nothing here, which is exactly what
  // lets the mode plumbing be tested without hardware.
  Widget host(OffClient offClient, {bool? camera}) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          offClientProvider.overrideWithValue(offClient),
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: ScanScreen(debugCameraOverride: camera)),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('a checksum typo is caught before any network is spent',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422004');
    expect(requests, 0, reason: 'invalid codes must not reach the API');
    expect(find.textContaining('check the numbers'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a valid code looks up the product and opens the confirm sheet',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 1);
    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('not-in-the-database is a calm state, not an error',
      (tester) async {
    await tester.pumpWidget(host(client(status: 404, body: 'nope')));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(find.textContaining('not in the shared database'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });

  // The camera keeps decoding under an open sheet; a repeat of the same code
  // must be swallowed, not stacked as a second sheet + second request.
  // Invoking the field's onSubmitted directly is the camera's exact path.
  void fireLikeCamera(WidgetTester tester, String code) {
    final field = tester.widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Barcode numbers'));
    field.onSubmitted!(code);
  }

  testWidgets('a second scan while the sheet is open is ignored',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 1);
    expect(find.text('Log it'), findsOneWidget);

    fireLikeCamera(tester, '3017620422003');
    await tester.pumpAndSettle();
    expect(requests, 1, reason: 'the latch must hold while the sheet is up');
    expect(find.text('Log it'), findsOneWidget,
        reason: 'no stacked second sheet');
    await unmount(tester);
  });

  testWidgets('the latch releases once the sheet is dismissed',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 1);

    // Swipe-away (tap the barrier) without logging.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Log it'), findsNothing);

    fireLikeCamera(tester, '3017620422003');
    await tester.pumpAndSettle();
    expect(requests, 2, reason: 'a fresh scan after dismissal is welcome');
    expect(find.text('Log it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('camera platforms: toggle + camera pane that reads by itself',
      (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<ScanMode>), findsOneWidget);
    expect(find.byType(ScannerView), findsOneWidget);
    expect(find.textContaining('reads on its own'), findsOneWidget);
    expect(find.byType(BarcodeSketch), findsNothing);
    await unmount(tester);
  });

  testWidgets('"Type it" removes the camera from the tree and shows the '
      'sketch', (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type it'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsNothing,
        reason: 'Type mode must dispose the camera, not hide it');
    expect(find.byType(BarcodeSketch), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the chosen mode survives leaving and reopening the screen',
      (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type it'));
    await tester.pumpAndSettle();
    await unmount(tester); // the 1s pump also flushes the pref write

    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsNothing);
    expect(find.byType(BarcodeSketch), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a camera that cannot start falls back to typing, calmly',
      (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();

    final view = tester.widget<ScannerView>(find.byType(ScannerView));
    view.onError!(Exception('CameraAccessDenied'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsNothing);
    expect(find.byType(BarcodeSketch), findsOneWidget);
    expect(find.textContaining("couldn't start"), findsOneWidget);
    expect(find.textContaining('CameraAccessDenied'), findsNothing,
        reason: 'a calm line, never raw exception text');
    await unmount(tester);
  });

  testWidgets('no camera: no toggle, the sketch teaches the small digits',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<ScanMode>), findsNothing);
    expect(find.byType(BarcodeSketch), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('logging from the confirm sheet returns you all the way home',
      (tester) async {
    // ScanScreen is pushed, not home — so the pop after a successful log
    // is observable.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        offClientProvider.overrideWithValue(client()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute(
                    builder: (_) => const ScanScreen())),
                child: const Text('open scanner'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open scanner'));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(find.text('Log it'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Log it'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // Sheet gone AND scanner gone: one log, zero leftover screens.
    expect(find.text('Log it'), findsNothing);
    expect(find.text('open scanner'), findsOneWidget);
    await unmount(tester);
  });
}
