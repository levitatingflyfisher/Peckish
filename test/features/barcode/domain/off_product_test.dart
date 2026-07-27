import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';

// Parsing Open Food Facts product JSON into the house MacroSet, under the
// null-is-unknown law: a product page missing protein must report protein as
// unknown, never 0 g.
void main() {
  Map<String, dynamic> product({Map<String, dynamic>? nutriments, String? servingSize, Object? servingQuantity}) => {
        'code': '3017620422003',
        'product': {
          'product_name': 'Nutella',
          'brands': 'Ferrero',
          if (servingSize != null) 'serving_size': servingSize,
          if (servingQuantity != null) 'serving_quantity': servingQuantity,
          'nutriments': nutriments ??
              {
                'energy-kcal_100g': 539,
                'proteins_100g': 6.3,
                'carbohydrates_100g': 57.5,
                'fat_100g': 30.9,
              },
        },
      };

  group('OffProduct.fromApiJson', () {
    test('parses name, brand, and per-100g macros', () {
      final p = OffProduct.fromApiJson(product(servingSize: '15 g', servingQuantity: 15));
      expect(p.barcode, '3017620422003');
      expect(p.name, 'Nutella');
      expect(p.brand, 'Ferrero');
      expect(p.per100g.kcal, 539);
      expect(p.per100g.proteinG, 6.3);
      expect(p.per100g.carbG, 57.5);
      expect(p.per100g.fatG, 30.9);
      expect(p.servingLabel, '15 g');
      expect(p.servingGrams, 15);
    });

    test('missing nutriment slots stay null — unknown is never zero', () {
      final p = OffProduct.fromApiJson(product(nutriments: {'energy-kcal_100g': 250}));
      expect(p.per100g.kcal, 250);
      expect(p.per100g.proteinG, isNull);
      expect(p.per100g.carbG, isNull);
      expect(p.per100g.fatG, isNull);
    });

    test('EU kJ-only labels convert energy_100g to kcal', () {
      final p = OffProduct.fromApiJson(product(nutriments: {'energy_100g': 2255}));
      expect(p.per100g.kcal, closeTo(539, 1));
    });

    test('serving_quantity tolerates the string shape OFF sometimes returns',
        () {
      final p = OffProduct.fromApiJson(product(servingSize: '2 rolls (56 g)', servingQuantity: '56'));
      expect(p.servingGrams, 56);
    });

    test('a product with no name falls back to the barcode as label', () {
      final json = product();
      (json['product'] as Map<String, dynamic>).remove('product_name');
      final p = OffProduct.fromApiJson(json);
      expect(p.name, '3017620422003');
    });

    test('displayName joins brand and name without duplication', () {
      final p = OffProduct.fromApiJson(product());
      expect(p.displayName, 'Nutella (Ferrero)');
      final noBrand = product();
      (noBrand['product'] as Map<String, dynamic>).remove('brands');
      expect(OffProduct.fromApiJson(noBrand).displayName, 'Nutella');
    });
  });
}
