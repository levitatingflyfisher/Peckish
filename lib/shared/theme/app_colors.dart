import 'package:flutter/material.dart';

/// Peckish's palette — paprika and butter on a flour cloth; a warm kitchen,
/// not a study. Every hue is a food: nothing here is purple, and nothing
/// here is alarm-red — paprika is appetite, clay is attention.
class AppColors {
  AppColors._();

  // Paprika — the identity: a warm, appetizing brick-orange
  // (app bar, primary buttons, the kcal number).
  static const paprika = Color(0xFFB0442A);
  static const paprika600 = Color(0xFF963A24);
  static const paprika700 = Color(0xFF7C2F1D);

  // Flour — warm kitchen linen (background); flour2 for cards/raised
  // surfaces. Warm but bright: a worktop, not parchment.
  static const flour = Color(0xFFFAF5EA);
  static const flour2 = Color(0xFFF1E9D8);

  // Butter — the warm accent: today, the one-tap peck, highlights.
  static const butter = Color(0xFFE0AC3F);

  // Sage — produce green: fresh, planned, checked off the list.
  static const sage = Color(0xFF6F8F52);

  // Clay — gentle attention. Never red: a heavy day is information, not
  // alarm. (Cocoa-brown, kept clearly apart from paprika.)
  static const clay = Color(0xFF8A5B3E);

  // Ink — text (warm umber-black, no plum in it)
  static const ink = Color(0xFF2B241E);

  // Stone — secondary text, disabled (warm grey)
  static const stone = Color(0xFF958D82);

  // Dark surfaces (warm charcoal family — embers, not aubergine)
  static const darkSurface = Color(0xFF221D18);
  static const darkSurface2 = Color(0xFF2D2620);
}
