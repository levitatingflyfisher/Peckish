/// The aisles a family list actually gets walked in.
enum GroceryAisle { produce, meat, dairy, bakery, frozen, pantry, other }

/// One line on the grocery list.
class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.name,
    required this.aisle,
    required this.checked,
    required this.manual,
    required this.createdAt,
    this.sourceRecipeId,
  });

  final String id;
  final String name;
  final GroceryAisle aisle;
  final bool checked;

  /// Manually added (survives every regeneration) vs generated from the plan
  /// (unchecked generated lines are replaced when the plan changes).
  final bool manual;
  final String? sourceRecipeId;
  final DateTime createdAt;
}

const _frozen = ['frozen', 'ice cream', 'popsicle'];
const _produce = [
  'apple',
  'banana',
  'orange',
  'lemon',
  'lime',
  'berr',
  'grape',
  'melon',
  'peach',
  'pear',
  'plum',
  'mango',
  'avocado',
  'tomato',
  'potato',
  'onion',
  'garlic',
  'carrot',
  'celery',
  'pepper',
  'lettuce',
  'spinach',
  'kale',
  'broccoli',
  'cauliflower',
  'cabbage',
  'cucumber',
  'zucchini',
  'squash',
  'mushroom',
  'corn',
  'green bean',
  'pea',
  'herb',
  'cilantro',
  'parsley',
  'basil',
  'ginger',
  'salad',
];
const _meat = [
  'beef',
  'chicken',
  'turkey',
  'pork',
  'ham',
  'bacon',
  'sausage',
  'steak',
  'lamb',
  'fish',
  'salmon',
  'tuna',
  'shrimp',
  'meat',
];
const _dairy = [
  'milk',
  'cheese',
  'cheddar',
  'mozzarella',
  'parmesan',
  'yogurt',
  'butter',
  'cream',
  'egg',
  'sour cream',
];
const _bakery = [
  'bread',
  'tortilla',
  'bun',
  'roll',
  'bagel',
  'muffin',
  'croissant',
  'pita',
  'naan',
];
const _pantry = [
  'flour',
  'sugar',
  'salt',
  'rice',
  'pasta',
  'noodle',
  'bean',
  'lentil',
  'oil',
  'vinegar',
  'sauce',
  'salsa',
  'broth',
  'stock',
  'canned',
  'cereal',
  'oat',
  'honey',
  'syrup',
  'spice',
  'cumin',
  'paprika',
  'cinnamon',
  'vanilla',
  'chocolate',
  'nut',
  'peanut',
  'almond',
  'chip',
  'cracker',
  'jam',
  'jelly',
];

/// Keyword aisle classifier — deliberately dumb, easily wrong, trivially
/// corrected by the user, and useful anyway (a roughly-sorted list beats an
/// unsorted one in a real store). Frozen wins first so "frozen chicken"
/// files under frozen, not meat.
GroceryAisle classifyAisle(String line) {
  final l = line.toLowerCase();
  bool hit(List<String> words) => words.any(l.contains);
  if (hit(_frozen)) return GroceryAisle.frozen;
  if (hit(_bakery)) return GroceryAisle.bakery;
  if (hit(_dairy)) return GroceryAisle.dairy;
  if (hit(_meat)) return GroceryAisle.meat;
  if (hit(_produce)) return GroceryAisle.produce;
  if (hit(_pantry)) return GroceryAisle.pantry;
  return GroceryAisle.other;
}
