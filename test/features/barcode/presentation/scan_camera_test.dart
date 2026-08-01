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
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// Two v0.8 phone-test findings, one screen:
//
//   "Should 'type barcode' and 'scan' be separate? I hate the extra click
//    when I'm not doing the same thing I did previous."
//   "The barcode recognition when uploading a photo from gallery still has
//    the camera screen going/on even when evaluating the barcode."
//
// The law that answers both: they were never really two modes — the digits
// field is live in every state — so the camera is simply UP when there is
// nothing to deal with, and DOWN the moment there is. Nothing is
// remembered, because nothing needs to be: camera-up already serves the
// typist at zero clicks, so remembering a preference could only ever cost
// one.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  final resolvers = <BarcodeResolver>[];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('peckish_scan_camera');
  });

  tearDown(() {
    for (final r in resolvers) {
      r.close();
    }
    resolvers.clear();
    tempDir.deleteSync(recursive: true);
  });

  String buildSlice(String name, {List<List<Object?>> products = const []}) {
    final path = p.join(tempDir.path, name);
    final raw = sql.sqlite3.open(path);
    raw.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
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

  BarcodeResolver resolverWith({String? usdaPath}) {
    final resolver = BarcodeResolver(
        installedDbPath: (id) async => id == 'usda' ? usdaPath : null);
    resolvers.add(resolver);
    return resolver;
  }

  OffClient client() => OffClient(client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'code': '3017620422003',
            'status': 'success',
            'product': {
              'product_name': 'Nutella',
              'nutriments': {'energy-kcal_100g': 539},
            },
          }),
          200,
        );
      }));

  Widget host({BarcodeResolver? resolver, bool startTyping = false}) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          offClientProvider.overrideWithValue(client()),
          barcodeResolverProvider.overrideWithValue(resolver ?? resolverWith()),
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: ScanScreen(
                debugCameraOverride: true, startTyping: startTyping)),
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

  testWidgets('the camera is up every time, whatever you did last time',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsOneWidget);

    // Park it, leave, come back.
    await tester.tap(find.byTooltip('Turn the camera off'));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsNothing);
    await unmount(tester);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsOneWidget,
        reason: 'a remembered choice can only ever cost a click — the '
            'digits field is live in camera mode anyway');
    await unmount(tester);
  });

  group('the Type door', () {
    // v0.9 collapsed the remembered Scan/Type toggle into one screen, which
    // was right — but it left one way in, and it was the camera's. Someone
    // who came to type paid a tap to put a preview down they never wanted.
    // Two doors, no memory: whichever you pick is right every time, because
    // you just picked it.
    testWidgets('opens with the camera already parked', (tester) async {
      await tester.pumpWidget(host(startTyping: true));
      await tester.pumpAndSettle();

      expect(find.byType(ScannerView), findsNothing,
          reason: 'you came to type — nothing should be filming');
      expect(find.byType(TextField), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the cursor is already in the field', (tester) async {
      await tester.pumpWidget(host(startTyping: true));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'here the keyboard IS the request — unlike the + sheet, '
              'where it arrived uninvited');
      await unmount(tester);
    });

    testWidgets('is a posture, not a mode — the next visit films again',
        (tester) async {
      await tester.pumpWidget(host(startTyping: true));
      await tester.pumpAndSettle();
      expect(find.byType(ScannerView), findsNothing);
      await unmount(tester);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byType(ScannerView), findsOneWidget,
          reason: 'nothing was remembered, which is the whole point');
      await unmount(tester);
    });
  });

  testWidgets('typing costs no toggle at all, camera up', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'the two were never really separate');
    await unmount(tester);
  });

  testWidgets('the camera stands down while a miss question is up',
      (tester) async {
    await tester.pumpWidget(
        host(resolver: resolverWith(usdaPath: buildSlice('usda.db'))));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsOneWidget);

    await submit(tester, '3017620422003');

    // The gallery-pick complaint: a decoded code leaves a question on
    // screen, and the preview kept running behind it.
    expect(find.text('Ask openfoodfacts.org'), findsOneWidget);
    expect(find.byType(ScannerView), findsNothing,
        reason: 'nothing is being scanned while you answer a question');
    expect(find.textContaining('3017620422003'), findsWidgets,
        reason: 'it should show what it read instead of a live preview');
    await unmount(tester);
  });

  testWidgets('Scan again puts the camera back', (tester) async {
    await tester.pumpWidget(
        host(resolver: resolverWith(usdaPath: buildSlice('usda.db'))));
    await tester.pumpAndSettle();
    await submit(tester, '3017620422003');
    expect(find.byType(ScannerView), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Scan again'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsOneWidget);
    expect(find.text('Ask openfoodfacts.org'), findsNothing,
        reason: 'the stale question dies with the code it was asking about');
    await unmount(tester);
  });

  testWidgets('the camera stays down under the confirm sheet', (tester) async {
    final usda = buildSlice('usda.db', products: [
      ['3017620422003', 'Nutella', null, 539.0, null, null, null, 15.0, '15 g']
    ]);
    await tester.pumpWidget(host(resolver: resolverWith(usdaPath: usda)));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');

    expect(find.text('Log it'), findsOneWidget);
    expect(find.byType(ScannerView), findsNothing,
        reason: 'a camera decoding under an open sheet is pure waste');
    await unmount(tester);
  });

  testWidgets('a camera turned off by hand stays off through a scan',
      (tester) async {
    await tester.pumpWidget(
        host(resolver: resolverWith(usdaPath: buildSlice('usda.db'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Turn the camera off'));
    await tester.pumpAndSettle();

    await submit(tester, '3017620422003');
    await tester.tap(find.widgetWithText(TextButton, 'Scan again'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerView), findsNothing,
        reason: 'clearing a stale code must not switch the camera on '
            'behind someone who deliberately turned it off');
    await unmount(tester);
  });
}
