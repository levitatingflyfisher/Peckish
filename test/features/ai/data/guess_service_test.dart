import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/guess_service.dart';

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
}
