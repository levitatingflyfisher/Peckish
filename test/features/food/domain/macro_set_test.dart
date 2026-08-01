import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

void main() {
  group('MacroSet', () {
    test('sums two sets slot-by-slot', () {
      const a = MacroSet(kcal: 100, proteinG: 10, carbG: 5, fatG: 2);
      const b = MacroSet(kcal: 50, proteinG: 1, carbG: 20, fatG: 0.5);
      final sum = a + b;
      expect(sum.kcal, 150);
      expect(sum.proteinG, 11);
      expect(sum.carbG, 25);
      expect(sum.fatG, 2.5);
    });

    test(
        'a null slot is treated as zero in sums but stays null when both are null',
        () {
      const a = MacroSet(kcal: 100);
      const b = MacroSet(kcal: 50, proteinG: 3);
      final sum = a + b;
      expect(sum.kcal, 150);
      expect(sum.proteinG, 3);
      // carb was null on both sides: still unknown, not fake-zero
      expect(sum.carbG, isNull);
      expect(sum.fatG, isNull);
    });

    test('scales by a factor, leaving null slots null', () {
      const a = MacroSet(kcal: 100, proteinG: 10);
      final scaled = a * 2.5;
      expect(scaled.kcal, 250);
      expect(scaled.proteinG, 25);
      expect(scaled.carbG, isNull);
    });

    test('per100g resolves grams into an absolute set', () {
      const per100 =
          MacroSet(kcal: 52, proteinG: 0.26, carbG: 13.81, fatG: 0.17);
      final apple = per100.forGrams(182); // 1 medium apple
      expect(apple.kcal, closeTo(94.6, 0.1));
      expect(apple.carbG, closeTo(25.1, 0.1));
    });

    test('zero is the fold identity', () {
      const entries = [
        MacroSet(kcal: 100, proteinG: 10),
        MacroSet(kcal: 30, carbG: 7),
      ];
      final total = entries.fold(MacroSet.zero, (a, b) => a + b);
      expect(total.kcal, 130);
      expect(total.proteinG, 10);
      expect(total.carbG, 7);
    });

    test('negative slot values clamp to zero on construction via clamped()',
        () {
      // Carb-by-difference lab artifacts in USDA foundation data can be
      // slightly negative; the importer clamps them.
      final clamped = const MacroSet(kcal: 127, carbG: -0.43).clamped();
      expect(clamped.carbG, 0);
      expect(clamped.kcal, 127);
    });
  });
}
