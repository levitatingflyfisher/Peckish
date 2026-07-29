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
import 'package:peckish/features/barcode/presentation/scan_screen.dart';
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

  Widget host(OffClient offClient) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          offClientProvider.overrideWithValue(offClient),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ScanScreen()),
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
}
