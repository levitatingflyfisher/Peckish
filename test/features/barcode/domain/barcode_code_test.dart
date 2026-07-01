import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';

// Manual entry is the universal path (the PWA has no camera scanner), so the
// validator is the trust boundary: it must accept every real GTIN shape and
// reject typos BEFORE a network call is spent on them.
void main() {
  group('BarcodeCode.tryParse', () {
    test('accepts a valid EAN-13', () {
      expect(BarcodeCode.tryParse('3017620422003')?.value, '3017620422003');
    });

    test('accepts a valid EAN-8', () {
      expect(BarcodeCode.tryParse('96385074')?.value, '96385074');
    });

    test('accepts a valid 12-digit UPC-A', () {
      expect(BarcodeCode.tryParse('036000291452')?.value, '036000291452');
    });

    test('strips spaces and hyphens before validating', () {
      expect(BarcodeCode.tryParse('3 017620-422003')?.value, '3017620422003');
    });

    test('rejects a checksum typo — the whole point of manual validation', () {
      expect(BarcodeCode.tryParse('3017620422004'), isNull);
    });

    test('rejects non-digits and wrong lengths', () {
      expect(BarcodeCode.tryParse('NUTELLA'), isNull);
      expect(BarcodeCode.tryParse('12345'), isNull);
      expect(BarcodeCode.tryParse(''), isNull);
      expect(BarcodeCode.tryParse('123456789012345'), isNull);
    });
  });
}
