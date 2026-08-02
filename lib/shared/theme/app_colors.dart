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
  // brick, never alarm-red — a heavy day is information, not a siren.
  static const clay = OhColors.hearth700;

  // Text.
  static const ink = OhColors.linen900;
  static const stone = OhColors.linen500;

  // Dark surfaces (the shared hearth-dark family — embers, not aubergine).
  static const darkSurface = OhColors.darkSurfaceBase;
  static const darkSurface2 = OhColors.darkSurfaceCard;
}
