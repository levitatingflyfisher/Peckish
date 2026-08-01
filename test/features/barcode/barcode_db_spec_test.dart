import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/barcode/data/barcode_db_spec.dart';

// The catalog is a trust boundary (the model_spec pattern, ADR-0010).
// These are FORMAT laws only — the integrator swaps in measured hashes
// and sizes at release time, so no test may pin a real hash or byte count.
void main() {
  test('the catalog carries both sources, USDA first (the default)', () {
    expect(barcodeDbCatalog, isNotEmpty);
    final ids = barcodeDbCatalog.map((s) => s.id).toList();
    expect(ids, contains('usda'));
    expect(ids, contains('off_us'));
    expect(barcodeDbCatalog.first.id, 'usda',
        reason: 'the list leads with the recommended slice (ADR-0010)');
  });

  test('ids and file names are unique — slices never collide on disk', () {
    final ids = barcodeDbCatalog.map((s) => s.id).toSet();
    final files = barcodeDbCatalog.map((s) => s.fileName).toSet();
    expect(ids.length, barcodeDbCatalog.length);
    expect(files.length, barcodeDbCatalog.length);
  });

  test('every entry is https, gzipped sqlite, and properly attributed', () {
    for (final spec in barcodeDbCatalog) {
      expect(spec.downloadUrl, startsWith('https://'));
      expect(spec.downloadUrl, endsWith('.sqlite.gz'));
      expect(spec.fileName, endsWith('.sqlite'));
      expect(spec.displayName, isNotEmpty);
      expect(spec.licenseName, isNotEmpty);
      expect(spec.licenseUrl, startsWith('https://'));
      expect(spec.attribution, isNotEmpty,
          reason: 'attribution travels with the data (ODbL / USDA citation)');
      expect(spec.approxBytes, greaterThanOrEqualTo(0));
    }
  });

  test('sha256Gz is PENDING or 64 lowercase hex — nothing in between', () {
    final hex64 = RegExp(r'^[0-9a-f]{64}$');
    for (final spec in barcodeDbCatalog) {
      expect(
        spec.sha256Gz == 'PENDING' || hex64.hasMatch(spec.sha256Gz),
        isTrue,
        reason: '${spec.id}: a malformed hash would brick every download',
      );
    }
  });

  test('the ODbL slice names its license on the spec itself', () {
    final off = barcodeDbCatalog.firstWhere((s) => s.id == 'off_us');
    expect(off.licenseName, contains('ODbL'));
    expect(off.attribution.toLowerCase(), contains('open food facts'));
  });
}
