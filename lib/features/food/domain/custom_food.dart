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
  });

  final String id;
  final String name;

  /// What one serving is called: '1 salad', '1 bowl', '2 rolls'.
  final String servingLabel;
  final MacroSet perServing;
  final DateTime createdAt;
  final bool archived;

  CustomFood copyWith({
    String? name,
    String? servingLabel,
    MacroSet? perServing,
    bool? archived,
  }) =>
      CustomFood(
        id: id,
        name: name ?? this.name,
        servingLabel: servingLabel ?? this.servingLabel,
        perServing: perServing ?? this.perServing,
        createdAt: createdAt,
        archived: archived ?? this.archived,
      );
}
