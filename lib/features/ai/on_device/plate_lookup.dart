import 'package:peckish/features/ai/on_device/plate_scan.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';

/// Resolves a plate label's search term against the bundled USDA spine:
/// best hit → its first household portion (or 100 g when none is
/// recorded) → absolute macros for that portion, clamped like every other
/// spine read. No hit → null; the draft line simply doesn't happen.
Future<PlateMatch?> plateLookup(UsdaFoodRepository usda, String query) async {
  final hits = await usda.search(query, limit: 1);
  if (hits.isEmpty) return null;
  final food = hits.first;
  final portions = await usda.portionsOf(food.fdcId);
  final grams = portions.isEmpty ? 100.0 : portions.first.grams;
  return (
    name: food.name,
    grams: grams,
    macros: food.per100g.forGrams(grams).clamped(),
  );
}
