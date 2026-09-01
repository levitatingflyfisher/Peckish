import 'package:flutter/widgets.dart';
import 'package:openhearth_design/openhearth_design.dart';

/// Peckish's semantic color names, aliased onto the shared OpenHearth
/// ramps — no raw hex lives in this app. Peckish wears the flagship
/// hearth terracotta (it IS the table-and-kitchen app); the names below
/// say what each color MEANS here, and openhearth_design says what it is.
class AppColors {
  AppColors._();

  // The identity: hearth terracotta (app bar accents, primary buttons,
  // the kcal number, today's bar).
  static const paprika = OhColors.hearth500;
  static const paprika600 = OhColors.hearth600;
  static const paprika700 = OhColors.hearth700;

  // Surfaces: warm linen (background; flour2 for cards/raised surfaces).
  static const flour = OhColors.linen50;
  static const flour2 = OhColors.linen100;

  // The warm accent: today, the one-tap peck, the carbs chip.
  static const butter = OhColors.amber400;

  // Produce green: fresh, planned, the protein chip, checked off.
  static const sage = OhColors.sage500;

  // Gentle attention (fat chip, failure lines, the delete swipe). Deep
  // brick, never alarm-red, on anything about the household's food: a
  // heavy day is information, not a siren. The fleet's urgency red (red +
  // icon + word, ohStyle colour language) is reserved for the one
  // irreversible system act, Erase all data's confirm.
  static const clay = OhColors.hearth700;

  // Text.
  static const ink = OhColors.linen900;

  /// Marks only: icons, borders, rules. Not text: as text it is 3.86:1 on
  /// flour (lens audit dmmt-01), under the 4.5:1 a sentence needs.
  static const stone = OhColors.linen500;

  /// Secondary text (captions, empty states, the one instructional line per
  /// screen): ohStyle's textSecondary role for the current theme, which
  /// clears 4.5:1 on every ground in both light and dark.
  static Color secondaryText(BuildContext context) =>
      OhColorRoles.of(context).textSecondary;

  // Dark surfaces (the shared hearth-dark family — embers, not aubergine).
  static const darkSurface = OhColors.darkSurfaceBase;
  static const darkSurface2 = OhColors.darkSurfaceCard;
}
