/// The on-device model catalog — pure Dart, no flutter_gemma import (the
/// Reckon rule: the spec layer must compile everywhere, including web).
///
/// Trust laws, enforced by test/features/ai/on_device/model_spec_test.dart:
/// litert-community only, ungated only, ZIP `.task` bundles only (this
/// MediaPipe build cannot load raw "TFL3" flatbuffers), and the default is
/// the SMALL model — parsing "two eggs and toast" is not a 4 GB job.
class PeckishModelSpec {
  const PeckishModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.modelType,
    required this.description,
    this.requiresToken = false,
  });

  final String id;
  final String displayName;
  final String fileName;
  final String downloadUrl;

  /// Approximate — progress bars only. NEVER used to judge whether a file
  /// on disk is complete (the Reckon scar: size-guessing deleted real
  /// models); completion is the atomic .part → final rename.
  final int sizeBytes;

  /// Mapped onto the plugin's ModelType by name in the io builder.
  final String modelType;
  final String description;
  final bool requiresToken;

  static const qwen05 = PeckishModelSpec(
    id: 'qwen-2.5-0.5b-it',
    displayName: 'Qwen 2.5 0.5B',
    fileName: 'qwen25-0-5b-it-q8.task',
    downloadUrl:
        'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/'
        'resolve/main/'
        'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    sizeBytes: 572000000, // ~546 MB
    modelType: 'qwen',
    description: 'Small and quick — right-sized for parsing what you ate. '
        '~550 MB, Apache-2.0, runs fully offline.',
  );

  static const qwen15 = PeckishModelSpec(
    id: 'qwen-2.5-1.5b-it',
    displayName: 'Qwen 2.5 1.5B',
    fileName: 'qwen25-1-5b-it-int8.task',
    downloadUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/'
        'resolve/main/'
        'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    sizeBytes: 1720000000, // ~1.6 GB
    modelType: 'qwen',
    description: 'Steadier on rambling descriptions. ~1.6 GB, Apache-2.0, '
        'runs fully offline — needs a phone with room to breathe.',
  );

  /// Default first — the order the UI shows.
  static const availableModels = [qwen05, qwen15];

  /// Null and unknown ids both land on the default: a deleted or renamed
  /// model must degrade to something real, never crash a settings screen.
  static PeckishModelSpec byId(String? id) => availableModels
      .firstWhere((m) => m.id == id, orElse: () => availableModels.first);
}
