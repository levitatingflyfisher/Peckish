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
  _FakeSession(this.reply);

  final String reply;
  static final List<Message> queries = [];

  @override
  Future<void> addQueryChunk(Message message) async => queries.add(message);

  @override
  Future<String> getResponse() async => reply;

  @override
  Stream<String> getResponseAsync() => Stream.fromIterable([reply]);

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
  _FakeModel(this.reply);

  final String reply;
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
    return _FakeSession(reply);
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
      modelLoader: (spec) async {
        loads++;
        expect(spec.id, 'qwen-2.5-0.5b-it');
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
      modelLoader: (_) async {
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
      modelLoader: (spec) async => loaded[spec.id] = _FakeModel('{"foods":[]}'),
    );

    await brain.complete('one');
    current = 'qwen-2.5-1.5b-it';
    await brain.complete('two');

    expect(loaded.keys, ['qwen-2.5-0.5b-it', 'qwen-2.5-1.5b-it']);
    expect(loaded['qwen-2.5-0.5b-it']!.closed, isTrue,
        reason: 'one resident model at a time — the old one is closed');
  });
}
