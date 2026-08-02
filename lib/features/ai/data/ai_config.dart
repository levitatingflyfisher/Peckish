/// Which brain answers the guesstimate box. [none] is the shipped default:
/// no key, no endpoint, no network — the AI tile simply doesn't exist until
/// the household configures one. [onDevice] is a downloaded model running
/// on this phone: nothing leaves the device, ever, not even the words.
/// [stove] is the household stove (domovoi): a home server the words travel
/// to encrypted, under a key both ends derive from the household phrase.
enum AiBackend { none, anthropic, openaiCompat, onDevice, stove }

/// The whole AI configuration, as one immutable value. Configuring IS the
/// opt-in: entering a key (or pointing at a local server) is the moment the
/// feature comes into being.
class AiConfig {
  const AiConfig({
    required this.backend,
    this.anthropicKey,
    this.baseUrl,
    this.model,
    this.stoveHost,
    this.stovePort,
    this.stovePhrase,
  });

  /// The stove's LAN port (HOME on a phone keypad) — must equal domovoi's
  /// `kStovePort`. Restated here (not imported) because this file compiles
  /// on web, where domovoi's export manifest cannot; the equality is
  /// test-bound in stove_brain_test.
  static const int defaultStovePort = 4663;

  final AiBackend backend;
  final String? anthropicKey;

  /// OpenAI-compatible server origin — `http://localhost:8080` for a
  /// llamafile, `http://localhost:11434/v1` for Ollama, or any gateway.
  final String? baseUrl;
  final String? model;

  /// The stove's LAN host — typed once, like sync pairing (no discovery).
  final String? stoveHost;

  /// Null means [defaultStovePort]; only an explicit override is stored.
  final int? stovePort;

  /// The household phrase (BIP39). Lives in [StoveSecretStore] at rest;
  /// rides the config value only in memory, like [anthropicKey].
  final String? stovePhrase;

  bool get configured => switch (backend) {
        AiBackend.none => false,
        AiBackend.anthropic =>
          anthropicKey != null && anthropicKey!.isNotEmpty,
        AiBackend.openaiCompat => baseUrl != null && baseUrl!.isNotEmpty,
        // Choosing it is the opt-in; whether the model file is actually on
        // disk is checked at guess time with a calm, actionable line.
        AiBackend.onDevice => true,
        // Both halves of the pairing: where the stove lives AND the phrase
        // that derives the only key it answers to.
        AiBackend.stove => stoveHost != null &&
            stoveHost!.isNotEmpty &&
            stovePhrase != null &&
            stovePhrase!.isNotEmpty,
      };
}
