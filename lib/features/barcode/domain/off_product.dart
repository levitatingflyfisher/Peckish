import 'package:peckish/features/food/domain/macro_set.dart';

/// One product as answered by Open Food Facts, reduced to what the diary
/// needs. Nothing else from the response is kept.
class OffProduct {
  const OffProduct({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.per100g,
    required this.servingLabel,
    required this.servingGrams,
  });

  final String barcode;
  final String name;
  final String? brand;

  /// Reference macros per 100 g, null-is-unknown like everything else.
  final MacroSet per100g;

  /// The label's serving description ('15 g', '2 rolls (56 g)'), when given.
  final String? servingLabel;
  final double? servingGrams;

  /// 'Nutella (Ferrero)' — or just the name when no brand is published.
  String get displayName => brand == null || brand!.isEmpty || name.contains(brand!)
      ? name
      : '$name ($brand)';

  /// Parses the v3 `{code, product: {...}}` envelope. Absent numbers stay
  /// null (unknown, never zero); an EU kJ-only label converts to kcal.
  factory OffProduct.fromApiJson(Map<String, dynamic> json) {
    final barcode = json['code']?.toString() ?? '';
    final product = json['product'];
    final p = product is Map ? product : const {};
    final nutriments = p['nutriments'] is Map ? p['nutriments'] as Map : const {};

    double? num100(String key) => _toDouble(nutriments['${key}_100g']);
    var kcal = num100('energy-kcal');
    if (kcal == null) {
      final kj = num100('energy');
      if (kj != null) kcal = kj / 4.184;
    }

    final name = p['product_name']?.toString();
    return OffProduct(
      barcode: barcode,
      name: (name == null || name.isEmpty) ? barcode : name,
      brand: p['brands']?.toString(),
      per100g: MacroSet(
        kcal: kcal,
        proteinG: num100('proteins'),
        carbG: num100('carbohydrates'),
        fatG: num100('fat'),
      ).clamped(),
      servingLabel: p['serving_size']?.toString(),
      servingGrams: _toDouble(p['serving_quantity']),
    );
  }

  /// OFF returns numbers as num or string depending on the product's edit
  /// history — tolerate both.
  static double? _toDouble(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };
}
