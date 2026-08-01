/// The one producer of user-facing quantity text (diary lines, qty prefills,
/// servings chips): whole numbers drop the pointless '.0' — '2 × serving',
/// never '2.0 × serving'. Fractions round at three decimals: enough for any
/// real portion (1/8 = 0.125) while a computed rescale's float noise
/// (249 × 1.1 = 273.90000000000003) never reaches the screen.
String formatQty(double v) {
  final r = (v * 1000).roundToDouble() / 1000;
  return r % 1 == 0 ? r.toInt().toString() : r.toString();
}
