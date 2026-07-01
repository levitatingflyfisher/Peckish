/// The one seam between the guess pipeline and whatever runs ON this
/// device. Pure Dart: [GuessService] and every test compile against this,
/// while the flutter_gemma implementation stays behind an io-only file
/// (web builds simply have no brain to hand over).
abstract class LocalBrain {
  /// One prompt in, the model's whole text answer out. Implementations may
  /// throw anything descriptive; the caller wraps failures calmly.
  Future<String> complete(String prompt);
}
