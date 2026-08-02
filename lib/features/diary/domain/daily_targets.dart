import 'package:peckish/features/food/domain/macro_set.dart';

/// What a daily number MEANS. A target is not always a bullseye:
///
/// - [about]   — land near it; both directions matter.
/// - [atLeast] — a floor; only falling short matters.
/// - [under]   — a cap; only going over matters.
///
/// The asymmetry is the whole point — "prioritize protein" is really
/// "protein is a floor", which no symmetric distance (or cosine) can say.
enum TargetRole {
  about,
  atLeast,
  under;

  /// Storage/wire strings are the enum names; anything unrecognized (a
  /// future role, a hand-edited file) reads as null — the axis default —
  /// never a crash.
  static TargetRole? tryParse(Object? raw) => switch (raw) {
        'about' => about,
        'atLeast' => atLeast,
        'under' => under,
        _ => null,
      };

  /// The role worn on its sleeve wherever a target is printed: floors read
  /// 'min 150g', caps 'max 2200 kcal', plain "about" targets stay bare
  /// numbers. Includes its own trailing space, so callers stay a plain
  /// '${role.mark}${number}'.
  ///
  /// These were ≥ and ≤ until v0.9, which was prettier and unreadable:
  /// neither bundled font has either glyph, so every target anyone ever set
  /// printed a tofu box. Words the app's own type can actually draw beat a
  /// symbol that depends on an OS fallback chain we don't ship — see
  /// test/shared/theme/font_coverage_test.dart.
  String get mark => switch (this) {
        about => '',
        atLeast => 'min ',
        under => 'max ',
      };
}

/// One macro axis of the day's targets, resolved and self-describing:
/// [of] reads this axis out of any [MacroSet], so engine code never
/// hand-matches axis names to fields.
typedef TargetAxis = ({
  String axis,
  double? target,
  TargetRole role,
  double? Function(MacroSet) of,
});

/// The user's static daily targets: four optional numbers, each with an
/// optional explicit [TargetRole]. A null role means the axis default —
/// protein is a floor, everything else is "about" — which makes the
/// minimal setup ("target calories, protein at least X") exactly two
/// typed numbers and zero extra decisions.
class DailyTargets {
  const DailyTargets({
    this.values = const MacroSet(),
    this.kcalRole,
    this.proteinRole,
    this.carbRole,
    this.fatRole,
  });

  final MacroSet values;
  final TargetRole? kcalRole;
  final TargetRole? proteinRole;
  final TargetRole? carbRole;
  final TargetRole? fatRole;

  bool get isSet =>
      values.kcal != null ||
      values.proteinG != null ||
      values.carbG != null ||
      values.fatG != null;

  TargetRole get resolvedKcalRole => kcalRole ?? TargetRole.about;
  TargetRole get resolvedProteinRole => proteinRole ?? TargetRole.atLeast;
  TargetRole get resolvedCarbRole => carbRole ?? TargetRole.about;
  TargetRole get resolvedFatRole => fatRole ?? TargetRole.about;

  /// The four axes with resolved roles — the shape the suggestion engine
  /// (and any per-axis UI) iterates.
  List<TargetAxis> get axes => [
        (
          axis: 'kcal',
          target: values.kcal,
          role: resolvedKcalRole,
          of: (m) => m.kcal,
        ),
        (
          axis: 'protein',
          target: values.proteinG,
          role: resolvedProteinRole,
          of: (m) => m.proteinG,
        ),
        (
          axis: 'carbs',
          target: values.carbG,
          role: resolvedCarbRole,
          of: (m) => m.carbG,
        ),
        (
          axis: 'fat',
          target: values.fatG,
          role: resolvedFatRole,
          of: (m) => m.fatG,
        ),
      ];

  @override
  bool operator ==(Object other) =>
      other is DailyTargets &&
      other.values == values &&
      other.kcalRole == kcalRole &&
      other.proteinRole == proteinRole &&
      other.carbRole == carbRole &&
      other.fatRole == fatRole;

  @override
  int get hashCode =>
      Object.hash(values, kcalRole, proteinRole, carbRole, fatRole);

  @override
  String toString() => 'DailyTargets($values, roles: '
      '$kcalRole/$proteinRole/$carbRole/$fatRole)';
}
