import 'package:peckish/features/food/domain/macro_set.dart';

/// One bundled USDA reference food. All macro values are per 100 g.
class UsdaFood {
  const UsdaFood({
    required this.fdcId,
    required this.source,
    required this.name,
    required this.per100g,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
  });

  final int fdcId;

  /// 'foundation' | 'sr' | 'survey' — which FDC dataset the row came from.
  final String source;
  final String name;
  final MacroSet per100g;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
}

/// A household portion for a USDA food ("1 medium (3\" dia)" → 182 g).
class UsdaPortion {
  const UsdaPortion({required this.label, required this.grams});

  final String label;
  final double grams;
}
