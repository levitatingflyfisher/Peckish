/// Which brain answers the guesstimate box. [none] is the shipped default:
/// no key, no endpoint, no network — the AI tile simply doesn't exist until
/// the household configures one.
enum AiBackend { none, anthropic, openaiCompat }

/// The whole AI configuration, as one immutable value. Configuring IS the
/// opt-in: entering a key (or pointing at a local server) is the moment the
/// feature comes into being.
class AiConfig {
  const AiConfig({
    required this.backend,
    this.anthropicKey,
    this.baseUrl,
    this.model,
  });

  final AiBackend backend;
  final String? anthropicKey;

  /// OpenAI-compatible server origin — `http://localhost:8080` for a
  /// llamafile, `http://localhost:11434/v1` for Ollama, or any gateway.
  final String? baseUrl;
  final String? model;

  bool get configured => switch (backend) {
        AiBackend.none => false,
        AiBackend.anthropic =>
          anthropicKey != null && anthropicKey!.isNotEmpty,
        AiBackend.openaiCompat => baseUrl != null && baseUrl!.isNotEmpty,
      };
}
