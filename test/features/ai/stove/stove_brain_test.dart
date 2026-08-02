import 'dart:convert';
import 'dart:io';

import 'package:domovoi/domovoi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/stove/stove_brain_factory.dart';

// The stove tier end-to-end: Peckish's adapter (phrase → BIP39 seed →
// StoveClient) against a REAL domovoi StoveServer and a fake OpenAI-compat
// upstream, all in-process on loopback. If the adapter mis-derives the
// secret by a single byte, the server's fail-closed 403 catches it here.
void main() {
  const phrase =
      'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';
  const wrongPhrase =
      'legal winner thank year wave sausage worth useful '
      'legal winner thank yellow';
  const answerText = '{"foods":[{"name":"Stew","kcal":300,"confidence":0.5}]}';

  late HttpServer upstream;
  late StoveServer server;

  // flutter_test swaps in an HttpOverrides that answers every request with
  // a 400; these tests need the real loopback wire.
  setUpAll(() async {
    HttpOverrides.global = null;

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': answerText},
          },
        ],
      }));
      await req.response.close();
    });

    final key =
        await DomovoiKeys.stoveKey(await DomovoiKeys.seedFromPhrase(phrase));
    server = StoveServer(
      0,
      key,
      Uri.parse('http://127.0.0.1:${upstream.port}/v1'),
      'test-model',
    );
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    await upstream.close(force: true);
  });

  AiConfig config({String? host, int? port, String? phraseOverride}) =>
      AiConfig(
        backend: AiBackend.stove,
        stoveHost: host ?? '127.0.0.1',
        stovePort: port ?? server.port,
        stovePhrase: phraseOverride ?? phrase,
      );

  test('the default port constant is domovoi\'s kStovePort', () {
    // The cross-package lock for the port the settings hint promises: the
    // web-safe constant restated in AiConfig must track domovoi's.
    expect(AiConfig.defaultStovePort, kStovePort);
  });

  test('stove is supported on io platforms', () {
    expect(stoveSupported, isTrue);
  });

  test('a full round trip: phrase in, upstream answer out', () async {
    final brain = createStoveBrain(config());
    expect(brain, isNotNull);
    expect(await brain!.complete('what did I eat'), answerText);
  });

  test('the wrong household phrase is refused, calmly', () async {
    final brain = createStoveBrain(config(phraseOverride: wrongPhrase))!;
    await expectLater(
      brain.complete('hi'),
      throwsA(isA<GuessException>().having(
          (e) => e.message, 'message', contains('household phrase'))),
    );
  });

  test('an unreachable stove is a calm message, not a stack trace',
      () async {
    final brain = createStoveBrain(config(port: 1))!;
    await expectLater(
      brain.complete('hi'),
      throwsA(isA<GuessException>()
          .having((e) => e.message, 'message', contains('stove'))),
    );
  });

  test('a missing host or phrase asks for Settings, not a crash', () async {
    final noHost = createStoveBrain(const AiConfig(
        backend: AiBackend.stove, stovePhrase: phrase))!;
    await expectLater(noHost.complete('hi'),
        throwsA(isA<GuessException>()));

    final noPhrase = createStoveBrain(
        const AiConfig(backend: AiBackend.stove, stoveHost: 'h'))!;
    await expectLater(noPhrase.complete('hi'),
        throwsA(isA<GuessException>()));
  });

  test('an invalid BIP39 phrase at ask time fails calmly', () async {
    final brain =
        createStoveBrain(config(phraseOverride: 'not a real phrase'))!;
    await expectLater(brain.complete('hi'),
        throwsA(isA<GuessException>()));
  });

  group('stovePhraseProblem (the settings validator)', () {
    test('a valid phrase has no problem', () async {
      expect(await stovePhraseProblem(phrase), isNull);
    });

    test('an invalid phrase gets a calm line, never a throw', () async {
      final problem = await stovePhraseProblem('twelve made up words here');
      expect(problem, isNotNull);
      expect(problem, isNot(contains('Exception')));
    });
  });
}
