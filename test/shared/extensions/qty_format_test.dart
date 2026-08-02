import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/shared/extensions/qty_format.dart';

// The one qty-to-text producer (entry tiles, qty/macro prefills, servings
// chips): whole numbers drop the '.0', fractions keep full precision.
void main() {
  group('formatQty', () {
    test('whole numbers drop the pointless .0', () {
      expect(formatQty(2), '2');
      expect(formatQty(2.0), '2');
      expect(formatQty(150.0), '150');
      expect(formatQty(0), '0');
    });

    test('fractions keep their full precision (the entry-tile canon)', () {
      expect(formatQty(1.5), '1.5');
      expect(formatQty(1.25), '1.25');
      expect(formatQty(0.75), '0.75');
    });

    test('float noise from computed rescales is rounded away, eighth '
        'portions survive', () {
      // 249 × 1.1 lands on 273.90000000000003 in doubles — a rescaled
      // quantity must never render the noise. Three decimals keeps every
      // real-world portion (1/8 = 0.125) intact.
      expect(formatQty(273.90000000000003), '273.9');
      expect(formatQty(0.125), '0.125');
      expect(formatQty(0.1 + 0.2), '0.3');
    });

    test('large whole doubles still read as integers', () {
      expect(formatQty(2000), '2000');
    });
  });
}
