/// The one seam between the guess pipeline and whatever runs ON this
/// device. Pure Dart: [GuessService] and every test compile against this,
/// while the flutter_gemma implementation stays behind an io-only file
/// (web builds simply have no brain to hand over).
abstract class LocalBrain {
  /// One prompt in, the model's whole text answer out. Implementations may
  /// throw anything descriptive; the caller wraps failures calmly.
  Future<String> complete(String prompt);
}

/// One "Check the model" run: pass/fail, how long it took, which backend
/// actually answered, the model id, the device ABI, and — on failure —
/// the real underlying error, not whatever calm copy the guess box shows.
/// Meant to be read off the screen and pasted into a report; the field
/// failure this answers is "local model definitely just doesn't work at
/// all" with nothing more to go on.
class ModelCheckResult {
  const ModelCheckResult({
    required this.ok,
    required this.elapsed,
    required this.backend,
    required this.modelId,
    required this.abi,
    this.error,
  });

  final bool ok;
  final Duration elapsed;

  /// 'gpu' or 'cpu-fallback'.
  final String backend;
  final String modelId;
  final String abi;
  final String? error;

  /// One copyable block, plain text, glyph-safe.
  String get report => [
        'pass: $ok',
        'elapsed: ${elapsed.inMilliseconds}ms',
        'backend: $backend',
        'model: $modelId',
        'abi: $abi',
        if (error != null) 'error: $error',
      ].join('\n');
}

/// Optional per-implementation diagnostics. Pure Dart, kept SEPARATE from
/// [LocalBrain] itself (rather than added there) so the existing
/// implementers — including every test fake — never have to grow a method
/// they cannot usefully implement; a caller checks `brain is
/// ModelDiagnostics` before calling it. Currently only the on-device Gemma
/// brain (gemma_brain_io.dart) implements this — an io-only file that must
/// never be imported from a widget the web build also compiles.
abstract class ModelDiagnostics {
  Future<ModelCheckResult> checkModel();
}
