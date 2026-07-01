import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';

void main() {
  test('classifies common household lines into aisles', () {
    expect(classifyAisle('2 honeycrisp apples'), GroceryAisle.produce);
    expect(classifyAisle('1 lb ground beef'), GroceryAisle.meat);
    expect(classifyAisle('rotisserie chicken'), GroceryAisle.meat);
    expect(classifyAisle('2 cups whole milk'), GroceryAisle.dairy);
    expect(classifyAisle('shredded cheddar cheese'), GroceryAisle.dairy);
    expect(classifyAisle('frozen peas'), GroceryAisle.frozen);
    expect(classifyAisle('sourdough bread'), GroceryAisle.bakery);
    expect(classifyAisle('1 can black beans'), GroceryAisle.pantry);
    expect(classifyAisle('olive oil'), GroceryAisle.pantry);
    expect(classifyAisle('birthday candles'), GroceryAisle.other);
  });

  test('frozen beats the food word — "frozen chicken" files under frozen', () {
    expect(classifyAisle('frozen chicken tenders'), GroceryAisle.frozen);
  });
}
