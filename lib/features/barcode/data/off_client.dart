import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';

/// The scanned product isn't in Open Food Facts (or has no product record).
class OffProductNotFound implements Exception {
  const OffProductNotFound(this.barcode);
  final String barcode;
  @override
  String toString() => 'No product found for $barcode.';
}

/// The lookup failed for a reason other than "not in the database".
class OffLookupException implements Exception {
  const OffLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The second of the app's two sanctioned network flows: one user-initiated
/// scan = one GET to Open Food Facts, parsed, discarded. Nothing is bundled
/// (OFF's ODbL share-alike never entangles the app) and nothing identifies
/// the user — the User-Agent names the app and its repo, per OFF's
/// identify-your-integration convention.
class OffClient {
  OffClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const userAgent =
      'Peckish/0.2 (https://github.com/levitatingflyfisher/Peckish)';

  /// Only what the diary needs — trimming fields keeps the response small
  /// and honest about what we consume.
  static const _fields =
      'product_name,brands,nutriments,serving_size,serving_quantity';

  /// A product record is a few KB; the cap keeps a hostile answer from
  /// ballooning memory (RecipeFetcher's posture).
  static const maxBytes = 2 * 1024 * 1024;

  Future<OffProduct> fetchProduct(BarcodeCode code) async {
    final url = Uri.https(
      'world.openfoodfacts.org',
      '/api/v3/product/${code.value}.json',
      {'fields': _fields},
    );

    final http.Response response;
    try {
      response = await _client.get(url, headers: {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      throw OffLookupException('Lookup failed — are you online? ($e)');
    }

    if (response.statusCode == 404) throw OffProductNotFound(code.value);
    if (response.statusCode != 200) {
      throw OffLookupException(
          'Open Food Facts answered ${response.statusCode} — try again in a '
          'moment.');
    }
    if (response.bodyBytes.length > maxBytes) {
      throw const OffLookupException('That answer was too large to trust.');
    }

    final Object decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const OffLookupException(
          'Open Food Facts sent something unreadable — try again in a '
          'moment.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const OffLookupException('Unexpected answer shape.');
    }
    // v3 wraps errors in a 200 + status envelope; v2 uses status 0/1.
    final status = decoded['status'];
    if (status == 'failure' || status == 0) {
      throw OffProductNotFound(code.value);
    }
    if (decoded['product'] is! Map) throw OffProductNotFound(code.value);

    return OffProduct.fromApiJson(decoded);
  }
}
