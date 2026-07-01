import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';

// The second of the app's two sanctioned network flows: one scan = one
// request to Open Food Facts, nothing stored server-side, nothing bundled
// (ODbL stays untangled — see docs). The client mirrors RecipeFetcher's
// posture: caps, timeouts, and honest errors.
void main() {
  final code = BarcodeCode.tryParse('3017620422003')!;

  MockClient happyClient({void Function(http.Request)? inspect}) =>
      MockClient((request) async {
        inspect?.call(request);
        return http.Response(
          jsonEncode({
            'code': '3017620422003',
            'status': 'success',
            'product': {
              'product_name': 'Nutella',
              'brands': 'Ferrero',
              'nutriments': {'energy-kcal_100g': 539},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

  group('OffClient.fetchProduct', () {
    test('requests the v3 product URL with a field allowlist and app UA',
        () async {
      late http.Request seen;
      final client = OffClient(client: happyClient(inspect: (r) => seen = r));
      await client.fetchProduct(code);

      expect(seen.url.host, 'world.openfoodfacts.org');
      expect(seen.url.path, '/api/v3/product/3017620422003.json');
      expect(seen.url.queryParameters['fields'], contains('nutriments'));
      // OFF asks integrations to identify themselves; ours identifies the
      // app, not a person.
      expect(seen.headers['User-Agent'], contains('Peckish/'));
      expect(seen.headers['User-Agent'], isNot(contains('@')));
    });

    test('returns the parsed product on success', () async {
      final p = await OffClient(client: happyClient()).fetchProduct(code);
      expect(p, isA<OffProduct>());
      expect(p.name, 'Nutella');
    });

    test('404 means honestly not-in-the-database', () async {
      final client = OffClient(
          client: MockClient((_) async => http.Response('not found', 404)));
      expect(() => client.fetchProduct(code),
          throwsA(isA<OffProductNotFound>()));
    });

    test('a v3 failure envelope with 200 status is also not-found', () async {
      final client = OffClient(
          client: MockClient((_) async => http.Response(
              jsonEncode({'code': '3017620422003', 'status': 'failure'}),
              200)));
      expect(() => client.fetchProduct(code),
          throwsA(isA<OffProductNotFound>()));
    });

    test('non-JSON garbage becomes a lookup exception, not a crash', () async {
      final client = OffClient(
          client: MockClient((_) async => http.Response('<html>oops', 200)));
      expect(
          () => client.fetchProduct(code), throwsA(isA<OffLookupException>()));
    });

    test('an oversized body is refused', () async {
      final client = OffClient(
          client:
              MockClient((_) async => http.Response('x' * (2 * 1024 * 1024 + 1), 200)));
      expect(
          () => client.fetchProduct(code), throwsA(isA<OffLookupException>()));
    });
  });
}
