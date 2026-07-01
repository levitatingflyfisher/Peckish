import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// One line of a saved meal — the same snapshot shape as a diary entry minus
/// the when. Logging the meal copies these into entries stamped now.
class SavedMealItem {
  const SavedMealItem({
    required this.id,
    required this.food,
    required this.label,
    required this.qty,
    required this.unitLabel,
    required this.grams,
    required this.macros,
  });

  final String id;
  final FoodRef food;
  final String label;
  final double qty;
  final String unitLabel;
  final double? grams;
  final MacroSet macros;
}

/// A staple: a named bundle of items relogged in one tap. The whole point of
/// the diary — a rotation covers most real meals, so the daily interaction is
/// recents + one tap, not search.
class SavedMeal {
  const SavedMeal({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
    required this.items,
    this.lastUsedAt,
    this.archived = false,
  });

  final String id;
  final String name;
  final int position;
  final DateTime createdAt;
  final List<SavedMealItem> items;
  final DateTime? lastUsedAt;
  final bool archived;

  MacroSet get totals =>
      items.fold(MacroSet.zero, (sum, i) => sum + i.macros);
}
