import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// A household-defined food — the Cafe Rio salad, grandma's rolls. Macros are
/// PER SERVING (not per 100 g): restaurant staples are "1 salad", not grams.
class CustomFood {
  const CustomFood({
    required this.id,
    required this.name,
    required this.servingLabel,
    required this.perServing,
    required this.createdAt,
    this.archived = false,
    this.barcode,
  });

  final String id;
  final String name;

  /// What one serving is called: '1 salad', '1 bowl', '2 rolls'.
  final String servingLabel;
  final MacroSet perServing;
  final DateTime createdAt;
  final bool archived;

  /// The barcode this food was saved from, or null when it never came off a
  /// package. Stored normalized (ADR-0010) so every GTIN padding of the same
  /// product is the same food — see [CustomFoodRepository.byBarcode].
  final String? barcode;

  /// This food as a one-tap relog template — one serving of it, at the
  /// macros it was saved with. Never inserted as-is: [relogEntry] mints the
  /// id, day and time.
  DiaryEntry asTemplateEntry() => DiaryEntry(
        id: 'saved:$id',
        day: DiaryEntry.dayOf(createdAt),
        at: createdAt,
        food: FoodRef.custom(id),
        label: name,
        qty: 1,
        unitLabel: servingLabel,
        grams: null,
        macros: perServing,
        source: EntrySource.tap,
        createdAt: createdAt,
      );

  CustomFood copyWith({
    String? name,
    String? servingLabel,
    MacroSet? perServing,
    bool? archived,
    String? barcode,
  }) =>
      CustomFood(
        id: id,
        name: name ?? this.name,
        servingLabel: servingLabel ?? this.servingLabel,
        perServing: perServing ?? this.perServing,
        createdAt: createdAt,
        archived: archived ?? this.archived,
        barcode: barcode ?? this.barcode,
      );
}
