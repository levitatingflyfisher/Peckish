/// The four numbers Peckish tracks, as one immutable value.
///
/// Every slot is nullable and null means *unknown*, never zero: a custom food
/// whose protein was never entered must not silently report 0 g protein.
/// Sums treat null as zero only when the other side has a value, so unknown +
/// unknown stays unknown while known + unknown keeps the known value.
class MacroSet {
  const MacroSet({this.kcal, this.proteinG, this.carbG, this.fatG});

  final double? kcal;
  final double? proteinG;
  final double? carbG;
  final double? fatG;

  static const zero = MacroSet(kcal: 0, proteinG: 0, carbG: 0, fatG: 0);

  MacroSet operator +(MacroSet other) => MacroSet(
        kcal: _add(kcal, other.kcal),
        proteinG: _add(proteinG, other.proteinG),
        carbG: _add(carbG, other.carbG),
        fatG: _add(fatG, other.fatG),
      );

  MacroSet operator *(double factor) => MacroSet(
        kcal: kcal == null ? null : kcal! * factor,
        proteinG: proteinG == null ? null : proteinG! * factor,
        carbG: carbG == null ? null : carbG! * factor,
        fatG: fatG == null ? null : fatG! * factor,
      );

  /// Treating this set as per-100g reference values, the absolute macros for
  /// [grams] of the food.
  MacroSet forGrams(double grams) => this * (grams / 100);

  /// Negative slot values clamped to zero — USDA carb-by-difference lab
  /// artifacts can be slightly negative and must never subtract from a day.
  MacroSet clamped() => MacroSet(
        kcal: _clamp(kcal),
        proteinG: _clamp(proteinG),
        carbG: _clamp(carbG),
        fatG: _clamp(fatG),
      );

  static double? _add(double? a, double? b) {
    if (a == null && b == null) return null;
    return (a ?? 0) + (b ?? 0);
  }

  static double? _clamp(double? v) => v == null ? null : (v < 0 ? 0 : v);

  @override
  bool operator ==(Object other) =>
      other is MacroSet &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbG == carbG &&
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbG, fatG);

  @override
  String toString() =>
      'MacroSet(kcal: $kcal, p: $proteinG, c: $carbG, f: $fatG)';
}
