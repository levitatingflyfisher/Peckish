import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/data/barcode_resolver.dart';
import 'package:peckish/features/barcode/data/barcode_resolver_provider.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/presentation/barcode_sketch.dart';
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// On this test platform (desktop VM) there is no camera, so the screen runs
// in its universal shape: manual digit entry. ADR-0010's law under test:
// the phone answers first, and NO code path reaches the network without the
// explicit "Ask openfoodfacts.org" tap. Local slices here are REAL sqlite
// files, so a hit exercises the exact read path the device runs.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  final resolvers = <BarcodeResolver>[];
  var requests = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('peckish_scan_screen');
    requests = 0;
  });

  tearDown(() {
    for (final r in resolvers) {
      r.close();
    }
    resolvers.clear();
    tempDir.deleteSync(recursive: true);
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

  // Builds a real slice file with the shared schema both sources use.
  String buildSlice(String name, {List<List<Object?>> products = const []}) {
    final path = p.join(tempDir.path, name);
    final raw = sql.sqlite3.open(path);
    raw.execute(
        'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    raw.execute('CREATE TABLE products('
        'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, '
        'kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL, '
        'serving_g REAL, serving_label TEXT)');
    for (final row in products) {
      raw.execute(
          'INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', row);
    }
    raw.dispose();
    return path;
  }

  // The scanned Nutella row, keyed as the normalizer stores it.
  List<Object?> nutellaRow() =>
      ['3017620422003', 'Nutella', 'Ferrero', 539.0, 6.3, 57.5, 30.9, 15.0, '15 g'];

  BarcodeResolver resolverWith({String? usdaPath, String? offPath}) {
    final resolver = BarcodeResolver(
        installedDbPath: (id) async => switch (id) {
              'usda' => usdaPath,
              'off_us' => offPath,
              _ => null,
            });
    resolvers.add(resolver);
    return resolver;
  }

  // camera:true forces the camera layout on this camera-less VM; the
  // ScannerView it mounts builds to nothing here, which is exactly what
  // lets the mode plumbing be tested without hardware.
  Widget host(OffClient offClient,
          {bool? camera, BarcodeResolver? resolver}) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          offClientProvider.overrideWithValue(offClient),
          barcodeResolverProvider.overrideWithValue(
              resolver ?? resolverWith()),
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

  final askButton = find.widgetWithText(OutlinedButton, 'Ask openfoodfacts.org');
  final getDbButton =
      find.widgetWithText(TextButton, 'Get the offline database');

  testWidgets('a checksum typo is caught before any network is spent',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422004');
    expect(requests, 0, reason: 'invalid codes must not reach the API');
    expect(find.textContaining('check the numbers'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a local hit opens the sheet with its source named — zero '
      'network', (tester) async {
    final usda = buildSlice('usda.db', products: [nutellaRow()]);
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 0,
        reason: 'a local answer must never touch the network');
    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    expect(find.text('From your phone — USDA database'), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a hit from the OFF slice credits Open Food Facts',
      (tester) async {
    final usda = buildSlice('usda.db'); // installed but empty
    final off = buildSlice('off.db', products: [nutellaRow()]);
    await tester.pumpWidget(host(client(),
        resolver: resolverWith(usdaPath: usda, offPath: off)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 0);
    expect(find.text('From your phone — Open Food Facts'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a miss is a state with an explicit ask — still zero network',
      (tester) async {
    final usda = buildSlice('usda.db'); // installed but empty
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 0, reason: 'a miss must not auto-fetch');
    expect(find.text("Not in your phone's food database."), findsOneWidget);
    expect(askButton, findsOneWidget);
    expect(getDbButton, findsNothing,
        reason: 'a phone that has the database is not pointed at it');
    await unmount(tester);
  });

  testWidgets('tapping Ask openfoodfacts.org spends exactly one request',
      (tester) async {
    final usda = buildSlice('usda.db');
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 0);

    await tester.tap(askButton);
    await tester.pumpAndSettle();
    expect(requests, 1, reason: 'one tap = one GET, never more');
    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    expect(find.text('From openfoodfacts.org'), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('with no local database the miss points at the download',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(requests, 0,
        reason: 'even with nothing installed, no auto-fetch — clean break');
    expect(find.textContaining('can live on your phone'), findsOneWidget);
    expect(askButton, findsOneWidget);
    expect(getDbButton, findsOneWidget);
    await unmount(tester);
  });

  testWidgets('not-found after asking is a calm state, not an error',
      (tester) async {
    await tester.pumpWidget(host(client(status: 404, body: 'nope')));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    await tester.tap(askButton);
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.textContaining('not in the shared database'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('a failed lookup keeps the Ask button up for a second tap',
      (tester) async {
    await tester.pumpWidget(host(client(status: 500, body: 'oops')));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    await tester.tap(askButton);
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.textContaining('try again'), findsOneWidget);
    expect(askButton, findsOneWidget,
        reason: 'a flaky connection deserves a retry without rescanning');
    await unmount(tester);
  });

  // The camera keeps decoding under an open sheet; a repeat of the same code
  // must be swallowed, not stacked as a second sheet. Invoking the field's
  // onSubmitted directly is the camera's exact path.
  void fireLikeCamera(WidgetTester tester, String code) {
    final field = tester.widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Barcode numbers'));
    field.onSubmitted!(code);
  }

  testWidgets('a second scan while the sheet is open is ignored',
      (tester) async {
    final usda = buildSlice('usda.db', products: [nutellaRow()]);
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(find.text('Log it'), findsOneWidget);

    fireLikeCamera(tester, '3017620422003');
    await tester.pumpAndSettle();
    expect(find.text('Log it'), findsOneWidget,
        reason: 'no stacked second sheet');
    expect(requests, 0);
    await unmount(tester);
  });

  testWidgets('the latch releases once the sheet is dismissed',
      (tester) async {
    final usda = buildSlice('usda.db', products: [nutellaRow()]);
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(find.text('Log it'), findsOneWidget);

    // Swipe-away (tap the barrier) without logging.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Log it'), findsNothing);

    fireLikeCamera(tester, '3017620422003');
    await tester.pumpAndSettle();
    expect(find.text('Log it'), findsOneWidget,
        reason: 'a fresh scan after dismissal is welcome');
    expect(requests, 0);
    await unmount(tester);
  });

  testWidgets('camera platforms: a camera pane that reads by itself',
      (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsOneWidget);
    expect(find.textContaining('reads on its own'), findsOneWidget);
    expect(find.byType(BarcodeSketch), findsNothing);
    // Typing needs no mode: the field is live under the preview.
    expect(find.byType(TextField), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('parking the camera removes it from the tree, not just hides it',
      (tester) async {
    await tester.pumpWidget(host(client(), camera: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Turn the camera off'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsNothing,
        reason: 'off must dispose the camera, not hide it');
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

  testWidgets('no camera: no camera button, the sketch teaches the digits',
      (tester) async {
    await tester.pumpWidget(host(client()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Turn the camera off'), findsNothing,
        reason: 'never offer to park a camera that does not exist');
    expect(find.byType(BarcodeSketch), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('logging from the confirm sheet returns you all the way home',
      (tester) async {
    final usda = buildSlice('usda.db', products: [nutellaRow()]);
    // ScanScreen is pushed, not home — so the pop after a successful log
    // is observable.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        offClientProvider.overrideWithValue(client()),
        barcodeResolverProvider
            .overrideWithValue(resolverWith(usdaPath: usda)),
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

  testWidgets('a scan opened for a past day carries that day to the sheet',
      (tester) async {
    final usda = buildSlice('usda.db', products: [nutellaRow()]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        offClientProvider.overrideWithValue(client()),
        barcodeResolverProvider
            .overrideWithValue(resolverWith(usdaPath: usda)),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const ScanScreen(day: '2026-07-30')),
    ));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    // The scan resolves the same way it always did — the only difference is
    // where the confirmed line will land, and the sheet says so out loud.
    expect(find.text('Nutella (Ferrero)'), findsOneWidget);
    expect(find.textContaining('Adding to'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a resolver failure resets the scanner calmly — never a '
      'stuck spinner', (tester) async {
    await tester.pumpWidget(
        host(client(), resolver: _ExplodingResolver()));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');

    // The screen's contract: failures are states with next steps. The
    // field must come back so the user can just try again.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.textContaining('try again'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an invalid re-entry clears the pending Ask — the button can '
      'never target a stale code', (tester) async {
    final usda = buildSlice('usda.db'); // installed but empty → miss
    await tester.pumpWidget(
        host(client(), resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    expect(askButton, findsOneWidget);

    // Mistyped follow-up: the old Ask must not survive aimed at the
    // previous code — two more taps would log the wrong food.
    await submit(tester, '3017620422004');
    expect(find.textContaining('check the numbers'), findsOneWidget);
    expect(askButton, findsNothing);
    await unmount(tester);
  });

  testWidgets('an Error escaping the online ask resets busy instead of '
      'bricking the screen', (tester) async {
    final usda = buildSlice('usda.db');
    final exploding = OffClient(
        client: MockClient((_) async => throw StateError('transport bug')));
    await tester.pumpWidget(
        host(exploding, resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    await tester.tap(askButton);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.textContaining('try again'), findsOneWidget);
    await unmount(tester);
  });
}

/// resolveLocal is documented never to throw — this stands in for the bug
/// that breaks that promise, proving the screen survives it anyway.
class _ExplodingResolver extends BarcodeResolver {
  _ExplodingResolver() : super(installedDbPath: (_) async => null);

  @override
  Future<BarcodeResolution> resolveLocal(BarcodeCode code) async =>
      throw StateError('resolver bug');
}
