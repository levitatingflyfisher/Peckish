import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/on_device/gemma_brain_io.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/model_spec.dart';

/// The Reckon harness: fake the SESSION layer, not the chat layer, so the
/// real [InferenceChat] machinery (token accounting, history) still runs —
/// the only way to unit-test the on-device path without hardware.
class _FakeSession implements InferenceModelSession {
  _FakeSession(this.reply, {this.hang = false});

  final String reply;

  /// Never completes — simulates a stuck delegate.
  final bool hang;
  static final List<Message> queries = [];

  @override
  Future<void> addQueryChunk(Message message) async => queries.add(message);

  @override
  Future<String> getResponse() async => reply;

  // A never-closed controller's stream neither emits nor completes — the
  // actual shape of a stuck delegate. Stream.empty() was tried first and
  // is wrong: an empty stream closes immediately, which raced the
  // timeout instead of triggering it.
  static final _hangController = StreamController<String>();

  @override
  Stream<String> getResponseAsync() =>
      hang ? _hangController.stream : Stream.fromIterable([reply]);

  @override
  Future<int> sizeInTokens(String text) async => 1;

  @override
  Future<void> stopGeneration() async {}

  @override
  SessionMetrics getSessionMetrics() =>
      throw UnimplementedError('metrics are not part of the guess path');

  @override
  Future<void> close() async {}
}

class _FakeModel extends InferenceModel {
  _FakeModel(this.reply, {this.hangOnSession = false});

  final String reply;

  /// The chat this model hands out never produces a token.
  final bool hangOnSession;
  double? lastTemperature;
  var closed = false;

  @override
  InferenceModelSession? get session => null;

  @override
  int get maxTokens => 4096;

  @override
  ModelFileType get fileType => ModelFileType.task;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    List<Tool> tools = const [],
    bool enableThinking = false,
  }) async {
    lastTemperature = temperature;
    return _FakeSession(reply, hang: hangOnSession);
  }

  @override
  PreferredBackend? get activeBackend => null;

  @override
  void addCloseListener(void Function() listener) {}

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tempDir;
  late ModelDownloadService downloads;

  setUp(() async {
    _FakeSession.queries.clear();
    tempDir = await Directory.systemTemp.createTemp('peckish_brain_test');
    downloads = ModelDownloadService(documentsDirectory: () async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> installFake(PeckishModelSpec spec) async {
    await File('${tempDir.path}/${spec.fileName}')
        .writeAsBytes(List.filled(2 * 1024 * 1024, 7));
  }

  test('a downloaded model answers, cool-headed and single-turn', () async {
    await installFake(PeckishModelSpec.qwen05);
    var loads = 0;
    final fake = _FakeModel('{"foods":[{"name":"Toast","kcal":80}]}');
    final brain = GemmaLocalBrain(
      downloads: downloads,
      modelId: () => 'qwen-2.5-0.5b-it',
      modelLoader: (spec, backend) async {
        loads++;
        expect(spec.id, 'qwen-2.5-0.5b-it');
        expect(backend, PreferredBackend.gpu,
            reason: 'gpu is the first attempt, every session');
        return fake;
      },
    );

    final answer = await brain.complete('prompt about toast');
    expect(answer, contains('Toast'));
    expect(fake.lastTemperature, 0.3, reason: 'a parser, not a storyteller');
    expect(
        _FakeSession.queries.any((m) => m.text.contains('prompt about toast')),
        isTrue,
        reason: 'the prompt reaches the session as the user turn');

    // Second guess: the resident model is reused, never reloaded.
    await brain.complete('prompt about eggs');
    expect(loads, 1);
  });

  test('a missing model is a calm actionable line, and nothing loads',
      () async {
    var loaderCalled = false;
    final brain = GemmaLocalBrain(
      downloads: downloads,
      modelId: () => 'qwen-2.5-0.5b-it',
      modelLoader: (_, __) async {
        loaderCalled = true;
        return _FakeModel('');
      },
    );

    await expectLater(
        brain.complete('anything'),
        throwsA(isA<GuessException>()
            .having((e) => e.message, 'message', contains('download'))));
    expect(loaderCalled, isFalse,
        reason: 'the gate runs before any native loading');
  });

  test('switching models closes the old one and loads the new', () async {
    await installFake(PeckishModelSpec.qwen05);
    await installFake(PeckishModelSpec.qwen15);
    var current = 'qwen-2.5-0.5b-it';
    final loaded = <String, _FakeModel>{};
    final brain = GemmaLocalBrain(
      downloads: downloads,
      modelId: () => current,
      modelLoader: (spec, __) async =>
          loaded[spec.id] = _FakeModel('{"foods":[]}'),
    );

    await brain.complete('one');
    current = 'qwen-2.5-1.5b-it';
    await brain.complete('two');

    expect(loaded.keys, ['qwen-2.5-0.5b-it', 'qwen-2.5-1.5b-it']);
    expect(loaded['qwen-2.5-0.5b-it']!.closed, isTrue,
        reason: 'one resident model at a time — the old one is closed');
  });

  group('GPU-path resilience', () {
    test('a GPU load failure retries once on CPU, and that answers',
        () async {
      await installFake(PeckishModelSpec.qwen05);
      final attempts = <PreferredBackend>[];
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        modelLoader: (spec, backend) async {
          attempts.add(backend);
          if (backend == PreferredBackend.gpu) {
            throw Exception('delegate init failed');
          }
          return _FakeModel('{"foods":[]}');
        },
      );

      final answer = await brain.complete('anything');
      expect(answer, isNotEmpty);
      expect(attempts, [PreferredBackend.gpu, PreferredBackend.cpu]);
    });

    test('the CPU fallback is sticky: the next guess never retries GPU',
        () async {
      await installFake(PeckishModelSpec.qwen05);
      await installFake(PeckishModelSpec.qwen15);
      var current = 'qwen-2.5-0.5b-it';
      var gpuAttempts = 0;
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => current,
        modelLoader: (spec, backend) async {
          if (backend == PreferredBackend.gpu) {
            gpuAttempts++;
            throw Exception('delegate init failed');
          }
          return _FakeModel('{"foods":[]}');
        },
      );

      await brain.complete('one'); // gpu fails, cpu answers
      current = 'qwen-2.5-1.5b-it'; // a DIFFERENT model, same session
      await brain.complete('two');

      expect(gpuAttempts, 1,
          reason: 'a delegate that failed once is not worth trying again '
              'on this device, this session');
    });

    test('both backends failing is one calm line, not a stack trace',
        () async {
      await installFake(PeckishModelSpec.qwen05);
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        modelLoader: (_, __) async => throw Exception('native crash'),
      );

      await expectLater(
        brain.complete('anything'),
        throwsA(isA<GuessException>()
            .having((e) => e.message, 'message', isNot(contains('native')))
            .having((e) => e.message, 'message', isNot(contains('Exception')))),
      );
    });
  });

  group('deadlines — a hang becomes a typed answer, not a forever-spinner',
      () {
    test('a load stuck past its deadline is a calm timeout, both backends',
        () async {
      await installFake(PeckishModelSpec.qwen05);
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        initTimeout: const Duration(milliseconds: 30),
        modelLoader: (_, __) => Completer<InferenceModel>().future, // hangs
      );

      await expectLater(
        brain.complete('anything'),
        throwsA(isA<GuessException>()),
      );
    });

    test('a guess stuck past its deadline is a calm timeout', () async {
      await installFake(PeckishModelSpec.qwen05);
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        completeTimeout: const Duration(milliseconds: 30),
        modelLoader: (_, __) async =>
            _FakeModel('unreachable', hangOnSession: true),
      );

      await expectLater(
        brain.complete('anything'),
        throwsA(isA<GuessException>()),
      );
    });

    test('production defaults are generous, not aggressive', () {
      final brain = GemmaLocalBrain(downloads: downloads, modelId: () => null);
      expect(brain.initTimeout, const Duration(seconds: 120));
      expect(brain.completeTimeout, const Duration(seconds: 180));
    });
  });

  group('checkModel — the phone-test evidence line', () {
    test('a pass reports elapsed time, backend, model id, and the ABI',
        () async {
      await installFake(PeckishModelSpec.qwen05);
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        modelLoader: (_, __) async => _FakeModel('ok'),
      );

      final result = await brain.checkModel();
      expect(result.ok, isTrue);
      expect(result.modelId, 'qwen-2.5-0.5b-it');
      expect(result.backend, 'gpu');
      expect(result.abi, isNotEmpty);
      expect(result.error, isNull);
    });

    test('a failure reports the REAL underlying error, not the calm copy',
        () async {
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        modelLoader: (_, __) async => _FakeModel(''),
      );

      // Not installed — the gate throws its calm line, but the diagnostic
      // must show what actually happened underneath, not a re-hash of the
      // same sentence a user already saw once.
      final result = await brain.checkModel();
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('checkModel reports which backend actually answered after a '
        'fallback', () async {
      await installFake(PeckishModelSpec.qwen05);
      final brain = GemmaLocalBrain(
        downloads: downloads,
        modelId: () => 'qwen-2.5-0.5b-it',
        modelLoader: (_, backend) async {
          if (backend == PreferredBackend.gpu) {
            throw Exception('delegate init failed');
          }
          return _FakeModel('ok');
        },
      );

      final result = await brain.checkModel();
      expect(result.ok, isTrue);
      expect(result.backend, 'cpu-fallback');
    });
  });
}
