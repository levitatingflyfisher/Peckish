import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';

/// Web build: no downloadable slice in the browser (ADR-0010 keeps web
/// online-only), so every lookup is a calm miss and nothing ever throws.
/// Touches no dart:io / sqlite3 ffi, so it is safe in `flutter build web`.
class LocalBarcodeDb {
  LocalBarcodeDb(this.path);

  final String path;

  OffProduct? lookup(BarcodeCode code) => null;

  Map<String, String> meta() => const {};

  void close() {}
}
