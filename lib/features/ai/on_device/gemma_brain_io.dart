import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/model_spec.dart';

/// The downloaded model, answering the guess box (Android). One resident
/// [InferenceModel] (loading a half-GB .task per guess would dwarf the
/// inference), a FRESH chat per call so guesses can't contaminate each
/// other, and the Reckon context lesson baked in: maxTokens 4096.
class GemmaLocalBrain implements LocalBrain {
  GemmaLocalBrain({
    required ModelDownloadService downloads,
    required String? Function() modelId,
    Future<InferenceModel> Function(PeckishModelSpec)? modelLoader,
  })  : _downloads = downloads,
        _modelId = modelId,
        _loader = modelLoader;

  final ModelDownloadService _downloads;

  /// Read per call — the settings dialog can switch models without any
  /// provider surgery; the brain notices on the next guess.
  final String? Function() _modelId;

  /// Injectable for tests; null = the real flutter_gemma load.
  final Future<InferenceModel> Function(PeckishModelSpec)? _loader;

  static bool _pluginReady = false;

  InferenceModel? _model;
  String? _loadedId;

  @override
  Future<String> complete(String prompt) async {
    final spec = PeckishModelSpec.byId(_modelId());
    final model = await _ensureModel(spec);
    // Low temperature, small topK: this is a parser being asked for JSON,
    // not a storyteller.
    final chat = await model.createChat(temperature: 0.3, topK: 20);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) buffer.write(response.token);
    }
    return buffer.toString();
  }

  Future<InferenceModel> _ensureModel(PeckishModelSpec spec) async {
    if (_model != null && _loadedId == spec.id) return _model!;

    // The gate runs BEFORE any native loading, so "not downloaded" is a
    // calm actionable line, never a runtime crash.
    if (!await _downloads.isDownloaded(spec)) {
      throw GuessException(
          '${spec.displayName} isn\'t on this phone yet — download it in '
          'Settings, then try again.');
    }

    final old = _model;
    _model = null;
    _loadedId = null;
    await old?.close();

    final loaded = await (_loader ?? _loadReal)(spec);
    _model = loaded;
    _loadedId = spec.id;
    return loaded;
  }

  Future<InferenceModel> _loadReal(PeckishModelSpec spec) async {
    if (!_pluginReady) {
      // flutter_gemma 0.13.x requires this one-time init before
      // installModel/getActiveModel — without it: "Bad state:
      // FlutterGemma not initialized!". Lazy here (first guess pays it)
      // so main.dart needs no platform shim.
      await FlutterGemma.initialize();
      _pluginReady = true;
    }
    final file = await _downloads.modelFile(spec);
    await FlutterGemma.installModel(modelType: _resolveModelType(spec.modelType))
        .fromFile(file.path)
        .install();
    return FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
    );
  }

  /// Spec strings → plugin enum by name, so the spec layer stays pure Dart.
  static ModelType _resolveModelType(String name) =>
      ModelType.values.firstWhere((t) => t.name == name,
          orElse: () => ModelType.gemmaIt);
}
