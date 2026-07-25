import 'package:peckish/features/food/domain/macro_set.dart';

/// What a logged line points at.
enum FoodKind { usda, custom, quick }

/// How a logged line was produced — provenance, kept on every entry so the
/// ledger can always say where a number came from.
enum EntrySource { tap, search, manual, ai }

/// Reference to a food: a bundled USDA row, a household custom food, or a
/// quick ad-hoc line that references nothing (label + macros only).
class FoodRef {
  const FoodRef.usda(int this.usdaFdcId)
      : kind = FoodKind.usda,
        customFoodId = null;
  const FoodRef.custom(String this.customFoodId)
      : kind = FoodKind.custom,
        usdaFdcId = null;
  const FoodRef.quick()
      : kind = FoodKind.quick,
        usdaFdcId = null,
        customFoodId = null;

  final FoodKind kind;
  final int? usdaFdcId;
  final String? customFoodId;

  /// Identity for recents-deduping: two entries of the same USDA/custom food
  /// are the same food; quick lines match by nothing but themselves.
  String identityKey(String label) => switch (kind) {
        FoodKind.usda => 'u:$usdaFdcId',
        FoodKind.custom => 'c:$customFoodId',
        FoodKind.quick => 'q:${label.toLowerCase()}',
      };

  @override
  bool operator ==(Object other) =>
      other is FoodRef &&
      other.kind == kind &&
      other.usdaFdcId == usdaFdcId &&
      other.customFoodId == customFoodId;

  @override
  int get hashCode => Object.hash(kind, usdaFdcId, customFoodId);
}

/// One line in the food ledger. Macros are a SNAPSHOT taken at log time:
/// editing a custom food later never rewrites history, and day totals are
/// pure sums over entries — never recomputed through today's food definitions.
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.day,
    required this.at,
    required this.food,
    required this.label,
    required this.qty,
    required this.unitLabel,
    required this.grams,
    required this.macros,
    required this.source,
    required this.createdAt,
  });

  final String id;

  /// Local calendar day 'YYYY-MM-DD' — stored as a string so DST shifts can
  /// never move an entry across midnight.
  final String day;
  final DateTime at;
  final FoodRef food;

  /// Display snapshot at log time (a renamed food doesn't rename history).
  final String label;
  final double qty;
  final String unitLabel;
  final double? grams;
  final MacroSet macros;
  final EntrySource source;
  final DateTime createdAt;

  DiaryEntry copyWith({
    String? day,
    DateTime? at,
    String? label,
    double? qty,
    String? unitLabel,
    double? grams,
    MacroSet? macros,
  }) =>
      DiaryEntry(
        id: id,
        day: day ?? this.day,
        at: at ?? this.at,
        food: food,
        label: label ?? this.label,
        qty: qty ?? this.qty,
        unitLabel: unitLabel ?? this.unitLabel,
        grams: grams ?? this.grams,
        macros: macros ?? this.macros,
        source: source,
        createdAt: createdAt,
      );
}
