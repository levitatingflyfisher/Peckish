import 'dart:async';
import 'dart:ffi' show Abi;

import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/model_spec.dart';

/// The downloaded model, answering the guess box (Android). One resident
/// [InferenceModel] (loading a half-GB .task per guess would dwarf the
/// inference), a FRESH chat per call so guesses can't contaminate each
/// other, and the Reckon context lesson baked in: maxTokens 4096.
///
/// Resilience, added after "local model definitely just doesn't work at
/// all" came back from a field test we could not reproduce: (a) a GPU
/// delegate that fails or hangs retries ONCE on CPU, sticky for the
/// session — a device that can't init the GPU path once is not going to
/// on the next guess either, and (b) every native call carries a generous
/// deadline, so a stuck delegate becomes a calm [GuessException] instead
/// of a forever-spinner.
class GemmaLocalBrain implements LocalBrain, ModelDiagnostics {
  GemmaLocalBrain({
    required ModelDownloadService downloads,
    required String? Function() modelId,
    Future<InferenceModel> Function(PeckishModelSpec, PreferredBackend)?
        modelLoader,
    this.initTimeout = const Duration(seconds: 120),
    this.completeTimeout = const Duration(seconds: 180),
  })  : _downloads = downloads,
        _modelId = modelId,
        _loader = modelLoader;

  final ModelDownloadService _downloads;

  /// Read per call — the settings dialog can switch models without any
  /// provider surgery; the brain notices on the next guess.
  final String? Function() _modelId;

  /// Injectable for tests; null = the real flutter_gemma load.
  final Future<InferenceModel> Function(PeckishModelSpec, PreferredBackend)?
      _loader;

  /// Generous — a cold load of a several-hundred-MB model on a modest
  /// phone is not a hang.
  final Duration initTimeout;

  /// This is a parser answering "what did you eat", not a storyteller —
  /// if it hasn't finished by here, the delegate is stuck, not thinking.
  final Duration completeTimeout;

  static bool _pluginReady = false;

  InferenceModel? _model;
  String? _loadedId;

  /// Sticky for the session: once the GPU delegate fails or hangs on this
  /// device, every later load — even for a different model — goes
  /// straight to CPU.
  PreferredBackend _backend = PreferredBackend.gpu;

  /// The real exception text from the last failure, kept for
  /// [checkModel] — the guess path itself only ever surfaces calm copy.
  String? _lastNativeError;

  String get _backendLabel =>
      _backend == PreferredBackend.gpu ? 'gpu' : 'cpu-fallback';

  @override
  Future<String> complete(String prompt) async {
    final spec = PeckishModelSpec.byId(_modelId());
    final model = await _ensureModel(spec);
    try {
      // Timing out the FUTURE, not the inner stream: flutter_gemma's
      // InferenceChat wraps the raw token stream through several of its
      // own filter stages (thinking-tag filter, stop-token filter), and a
      // .timeout() on just the outermost stream did not reliably fire
      // against those — a wrapped hang sailed past a 30ms deadline in
      // testing. Timing out the whole awaited operation is immune to
      // however many stream stages sit underneath.
      return await _completeOnce(model, prompt).timeout(completeTimeout);
    } on TimeoutException catch (e) {
      _lastNativeError = e.toString();
      throw GuessException(
          "${spec.displayName} is taking too long to answer — try again, "
          'or a smaller model in Settings might be steadier on this phone.');
    }
  }

  /// Low temperature, small topK: this is a parser being asked for JSON,
  /// not a storyteller.
  Future<String> _completeOnce(InferenceModel model, String prompt) async {
    final chat = await model.createChat(temperature: 0.3, topK: 20);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) buffer.write(response.token);
    }
    return buffer.toString();
  }

  /// Runs a tiny canned prompt through whatever is currently configured
  /// and reports what actually happened — turns the next "doesn't work"
  /// into something pasteable into a report.
  @override
  Future<ModelCheckResult> checkModel() async {
    final spec = PeckishModelSpec.byId(_modelId());
    final stopwatch = Stopwatch()..start();
    try {
      final answer = await complete('Reply with only the word: ok');
      stopwatch.stop();
      return ModelCheckResult(
        ok: answer.trim().isNotEmpty,
        elapsed: stopwatch.elapsed,
        backend: _backendLabel,
        modelId: spec.id,
        abi: Abi.current().toString(),
      );
    } on Object catch (e) {
      stopwatch.stop();
      return ModelCheckResult(
        ok: false,
        elapsed: stopwatch.elapsed,
        backend: _backendLabel,
        modelId: spec.id,
        abi: Abi.current().toString(),
        error: _lastNativeError ?? e.toString(),
      );
    }
  }

  Future<InferenceModel> _ensureModel(PeckishModelSpec spec) async {
    if (_model != null && _loadedId == spec.id) return _model!;

    // The gate runs BEFORE any native loading, so "not downloaded" is a
    // calm actionable line, never a runtime crash.
    if (!await _downloads.isDownloaded(spec)) {
      _lastNativeError = 'model not downloaded: ${spec.id}';
      throw GuessException(
          '${spec.displayName} isn\'t on this phone yet — download it in '
          'Settings, then try again.');
    }

    final old = _model;
    _model = null;
    _loadedId = null;
    await old?.close();

    final loaded = await _loadWithFallback(spec);
    _model = loaded;
    _loadedId = spec.id;
    return loaded;
  }

  /// (a): a GPU-path failure — including a hang past [initTimeout] —
  /// retries ONCE on CPU. [_backend] flips and stays flipped.
  Future<InferenceModel> _loadWithFallback(PeckishModelSpec spec) async {
    final triedGpu = _backend == PreferredBackend.gpu;
    try {
      return await _loadTimed(spec, _backend);
    } on Object catch (e) {
      _lastNativeError = e.toString();
      if (!triedGpu) {
        throw GuessException(_loadFailureMessage(spec));
      }
      _backend = PreferredBackend.cpu;
      try {
        return await _loadTimed(spec, _backend);
      } on Object catch (e2) {
        _lastNativeError = e2.toString();
        throw GuessException(_loadFailureMessage(spec));
      }
    }
  }

  /// (b): every native load carries a deadline — a hang and an outright
  /// failure are handled identically by [_loadWithFallback] above.
  Future<InferenceModel> _loadTimed(
          PeckishModelSpec spec, PreferredBackend backend) =>
      (_loader ?? _loadReal)(spec, backend).timeout(initTimeout);

  static String _loadFailureMessage(PeckishModelSpec spec) =>
      "${spec.displayName} couldn't load on this phone — 'Check the "
      "model' in Settings can say more, or try a smaller model.";

  Future<InferenceModel> _loadReal(
      PeckishModelSpec spec, PreferredBackend backend) async {
    if (!_pluginReady) {
      // flutter_gemma 0.13.x requires this one-time init before
      // installModel/getActiveModel — without it: "Bad state:
      // FlutterGemma not initialized!". Lazy here (first guess pays it)
      // so main.dart needs no platform shim.
      await FlutterGemma.initialize();
      _pluginReady = true;
    }
    final file = await _downloads.modelFile(spec);
    await FlutterGemma.installModel(
            modelType: _resolveModelType(spec.modelType))
        .fromFile(file.path)
        .install();
    return FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: backend,
    );
  }

  /// Spec strings → plugin enum by name, so the spec layer stays pure Dart.
  static ModelType _resolveModelType(String name) => ModelType.values
      .firstWhere((t) => t.name == name, orElse: () => ModelType.gemmaIt);
}
