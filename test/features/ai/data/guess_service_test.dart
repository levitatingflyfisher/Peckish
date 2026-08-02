import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/stove/stove_brain.dart';

// Two backends, one contract: the user's words go ONLY to the endpoint they
// configured, and what comes back is parsed as a draft. Key entry is the
// cloud opt-in; a localhost OpenAI-compatible endpoint is the local-first
// path.
void main() {
  group('GuessService — Anthropic BYOK', () {
    const config = AiConfig(
      backend: AiBackend.anthropic,
      anthropicKey: 'sk-ant-test',
      model: 'claude-sonnet-4-6',
    );

    test('sends the messages request with the key and gets a draft back',
        () async {
      late http.Request seen;
      final service = GuessService(
        config: config,
        httpClient: MockClient((r) async {
          seen = r;
          return http.Response(
            jsonEncode({
              'content': [
                {
                  'type': 'text',
                  'text': '{"foods":[{"name":"Apple","kcal":95,'
                      '"confidence":0.9}]}'
                }
              ]
            }),
            200,
          );
        }),
      );

      final guess = await service.guess('an apple');
      expect(guess.foods.single.name, 'Apple');
      expect(seen.url.toString(),
          'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], 'sk-ant-test');
      expect(seen.headers['anthropic-version'], isNotNull);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-sonnet-4-6');
      expect(body['messages'], isA<List<dynamic>>());
      expect(seen.body, contains('an apple'));
    });

    test('a non-200 becomes a friendly exception', () async {
      final service = GuessService(
        config: config,
        httpClient:
            MockClient((_) async => http.Response('{"error":"nope"}', 401)),
      );
      expect(() => service.guess('an apple'),
          throwsA(isA<GuessException>()));
    });
  });

  group('GuessService — OpenAI-compatible (the local path)', () {
    const config = AiConfig(
      backend: AiBackend.openaiCompat,
      baseUrl: 'http://localhost:8080',
      model: 'qwen2.5:1.5b',
    );

    test('posts to /v1/chat/completions and reads the choice', () async {
      late http.Request seen;
      final service = GuessService(
        config: config,
        httpClient: MockClient((r) async {
          seen = r;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '{"foods":[{"name":"Rice","kcal":230,"confidence":0.6}]}'
                  }
                }
              ]
            }),
            200,
          );
        }),
      );

      final guess = await service.guess('a bowl of rice');
      expect(guess.foods.single.name, 'Rice');
      expect(seen.url.toString(),
          'http://localhost:8080/v1/chat/completions');
      expect(seen.body, contains('a bowl of rice'));
    });

    test('a base URL already ending in /v1 is not doubled', () async {
      late http.Request seen;
      final service = GuessService(
        config: const AiConfig(
          backend: AiBackend.openaiCompat,
          baseUrl: 'http://localhost:11434/v1',
          model: 'qwen2.5:1.5b',
        ),
        httpClient: MockClient((r) async {
          seen = r;
          return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{"foods":[]}'}
                  }
                ]
              }),
              200);
        }),
      );
      await service.guess('nothing');
      expect(seen.url.toString(),
          'http://localhost:11434/v1/chat/completions');
    });
  });

  test('an unconfigured service refuses to guess', () {
    final service = GuessService(config: const AiConfig(backend: AiBackend.none));
    expect(() => service.guess('an apple'), throwsA(isA<GuessException>()));
  });

  group('GuessService — on-device brain', () {
    const config = AiConfig(backend: AiBackend.onDevice);

    test('the prompt goes to the local brain and the answer is parsed',
        () async {
      String? seenPrompt;
      final service = GuessService(
        config: config,
        localBrain: _FakeBrain((prompt) async {
          seenPrompt = prompt;
          return 'Sure! {"foods":[{"name":"Toast","kcal":80,'
              '"confidence":0.6}]}';
        }),
      );

      final guess = await service.guess('a slice of toast');
      expect(guess.foods.single.name, 'Toast');
      expect(seenPrompt, contains('a slice of toast'),
          reason: 'the one canonical prompt, same as every backend');
      expect(seenPrompt, contains('JSON'));
    });

    test('no brain on this platform → a calm refusal, not a crash', () {
      final service = GuessService(config: config);
      expect(() => service.guess('an apple'),
          throwsA(isA<GuessException>()));
    });

    test('a brain failure becomes a friendly exception', () {
      final service = GuessService(
        config: config,
        localBrain: _FakeBrain((_) async =>
            throw StateError('model file missing')),
      );
      expect(() => service.guess('an apple'),
          throwsA(isA<GuessException>()));
    });
  });

  group('GuessService — the household stove', () {
    const config = AiConfig(
      backend: AiBackend.stove,
      stoveHost: '192.168.1.20',
      stovePhrase: 'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon about',
    );

    test('the prompt goes to the stove brain and the answer is parsed',
        () async {
      String? seenPrompt;
      final service = GuessService(
        config: config,
        stoveBrain: _FakeStove((prompt) async {
          seenPrompt = prompt;
          return '{"foods":[{"name":"Stew","kcal":300,"confidence":0.5}]}';
        }),
      );

      final guess = await service.guess('a bowl of stew');
      expect(guess.foods.single.name, 'Stew');
      expect(seenPrompt, contains('a bowl of stew'),
          reason: 'the one canonical prompt, same as every backend');
    });

    test('no stove on this platform → a calm refusal, not a crash', () {
      final service = GuessService(config: config);
      expect(
          () => service.guess('an apple'), throwsA(isA<GuessException>()));
    });

    test("the stove's own calm message rides through untouched", () {
      final service = GuessService(
        config: config,
        stoveBrain: _FakeStove((_) async => throw const GuessException(
            'The stove is not answering. Is it on and on this network?')),
      );
      expect(
          service.guess('an apple'),
          throwsA(isA<GuessException>().having((e) => e.message, 'message',
              contains('stove is not answering'))));
    });

    test('an unexpected stove failure becomes a friendly exception', () {
      final service = GuessService(
        config: config,
        stoveBrain:
            _FakeStove((_) async => throw StateError('wire exploded')),
      );
      expect(
          () => service.guess('an apple'), throwsA(isA<GuessException>()));
    });

    test('a stove config without host or phrase is not configured', () {
      const bare = AiConfig(backend: AiBackend.stove, stoveHost: 'h');
      final service =
          GuessService(config: bare, stoveBrain: _FakeStove((_) async => ''));
      expect(
          () => service.guess('an apple'), throwsA(isA<GuessException>()));
    });
  });
}

class _FakeBrain implements LocalBrain {
  _FakeBrain(this.onComplete);
  final Future<String> Function(String prompt) onComplete;
  @override
  Future<String> complete(String prompt) => onComplete(prompt);
}

class _FakeStove implements StoveBrain {
  _FakeStove(this.onComplete);
  final Future<String> Function(String prompt) onComplete;
  @override
  Future<String> complete(String prompt) => onComplete(prompt);
}
