/// The offline barcode-slice catalog — pure Dart, compiles everywhere
/// (ADR-0010). Two sources, IDENTICAL schema, separate files, never merged:
/// the ODbL source-purity law keeps Open Food Facts rows out of the USDA
/// file so each database carries exactly its own license.
///
/// Format laws are enforced by test/features/barcode/barcode_db_spec_test.dart.
/// `sha256Gz` and `approxBytes` ship as 'PENDING'/0 until the release
/// integrator measures the built artifacts — a download against a PENDING
/// hash fails closed before any network (see the download service).
class BarcodeDbSpec {
  const BarcodeDbSpec({
    required this.id,
    required this.displayName,
    required this.downloadUrl,
    required this.fileName,
    required this.sha256Gz,
    required this.licenseName,
    required this.licenseUrl,
    required this.attribution,
    required this.approxBytes,
  });

  final String id;
  final String displayName;
  final String downloadUrl;
  final String fileName;

  /// SHA-256 of the compressed release asset, checked before decompression.
  /// 'PENDING' means the integrator hasn't measured it yet — never
  /// downloadable in that state.
  final String sha256Gz;

  final String licenseName;
  final String licenseUrl;

  /// Travels with the data by law: USDA citation is requested, ODbL
  /// attribution is required. Shown wherever the slice is offered.
  final String attribution;

  /// Approximate — progress bars and "is there room?" copy only, never a
  /// completeness check (completion is the atomic rename).
  final int approxBytes;
}

/// USDA first — the recommended slice (public domain, no obligations).
const List<BarcodeDbSpec> barcodeDbCatalog = [
  BarcodeDbSpec(
    id: 'usda',
    displayName: 'US packaged foods (USDA)',
    downloadUrl: 'https://github.com/levitatingflyfisher/Peckish/releases/'
        'download/v0-data/peckish-barcodes-usda-2025-12-18.sqlite.gz',
    fileName: 'barcodes_usda_v1.sqlite',
    sha256Gz: 'PENDING',
    licenseName: 'CC0 1.0 (public domain)',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    attribution: 'U.S. Department of Agriculture, Agricultural Research '
        'Service. FoodData Central Branded Foods, 2025.',
    approxBytes: 0,
  ),
  BarcodeDbSpec(
    id: 'off_us',
    displayName: 'Open Food Facts (US slice)',
    downloadUrl: 'https://github.com/levitatingflyfisher/Peckish/releases/'
        'download/v0-data/peckish-barcodes-off-us.sqlite.gz',
    fileName: 'barcodes_off_us_v1.sqlite',
    sha256Gz: 'PENDING',
    licenseName: 'Open Database License (ODbL) v1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    attribution: 'Contains information from Open Food Facts '
        '(openfoodfacts.org), made available under the Open Database License.',
    approxBytes: 0,
  ),
];

/// A finished .gz whose hash doesn't match its catalog entry. The file is
/// already deleted when this is thrown — nothing corrupt survives to be
/// resumed or installed.
///
/// Lives beside the catalog (not in the io variant) so UI catch-clauses
/// compile on every platform from one import.
class BarcodeDbIntegrityException implements Exception {
  const BarcodeDbIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'BarcodeDbIntegrityException: $message';
}
