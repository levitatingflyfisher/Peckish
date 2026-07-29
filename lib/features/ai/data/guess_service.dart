import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/domain/meal_guess.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';

/// The guess couldn't be made — configuration, network, or the service
/// itself. The message is written for the sheet, not a log file.
class GuessException implements Exception {
  const GuessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sends the user's words to exactly the backend they configured — nothing
/// else ever leaves the device — and parses the answer into a draft.
class GuessService {
  GuessService({required this.config, http.Client? httpClient, this.localBrain})
      : _http = httpClient ?? http.Client();

  final AiConfig config;
  final http.Client _http;

  /// The on-device model, when this platform has one (null on web).
  final LocalBrain? localBrain;

  static const _timeout = Duration(seconds: 60);

  Future<MealGuess> guess(String description) async {
    if (!config.configured) {
      throw const GuessException(
          'No AI is set up yet — add a key or a local server in Settings.');
    }
    final raw = switch (config.backend) {
      AiBackend.anthropic => await _askAnthropic(description),
      AiBackend.openaiCompat => await _askOpenAiCompat(description),
      AiBackend.onDevice => await _askLocalBrain(description),
      AiBackend.none => throw StateError('unreachable'),
    };
    return MealGuess.parse(raw);
  }

  Future<String> _askLocalBrain(String description) async {
    final brain = localBrain;
    if (brain == null) {
      throw const GuessException(
          "On-device AI isn't available on this platform — pick another "
          'option in Settings.');
    }
    try {
      return await brain.complete(MealGuess.promptFor(description));
    } on GuessException {
      rethrow;
    } on Exception catch (_) {
      throw const GuessException(
          "The on-device model couldn't answer — check that it finished "
          'downloading in Settings, then try again.');
    } on Error catch (_) {
      throw const GuessException(
          "The on-device model couldn't answer — check that it finished "
          'downloading in Settings, then try again.');
    }
  }

  Future<String> _askAnthropic(String description) async {
    final res = await _post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': config.anthropicKey!,
        'anthropic-version': '2023-06-01',
        // The documented header that lets a browser page call the API
        // directly — BYOK on the PWA without any proxy in between.
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: {
        'model': config.model ?? 'claude-sonnet-4-6',
        'max_tokens': 1024,
        'messages': [
          {'role': 'user', 'content': MealGuess.promptFor(description)},
        ],
      },
    );
    final content = res['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map && first['text'] is String) {
        return first['text'] as String;
      }
    }
    throw const GuessException('The AI answered in an unexpected shape.');
  }

  Future<String> _askOpenAiCompat(String description) async {
    // Users paste every base shape the ecosystem produces; don't double a
    // /v1 they already wrote (the Reckon lesson).
    final base = config.baseUrl!.replaceAll(RegExp(r'/+$'), '');
    final suffix =
        base.endsWith('/v1') ? '/chat/completions' : '/v1/chat/completions';
    final res = await _post(
      Uri.parse('$base$suffix'),
      headers: {'content-type': 'application/json'},
      body: {
        'model': config.model ?? '',
        'messages': [
          {'role': 'user', 'content': MealGuess.promptFor(description)},
        ],
        'temperature': 0.3,
      },
    );
    final choices = res['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    }
    throw const GuessException('The AI answered in an unexpected shape.');
  }

  Future<Map<String, dynamic>> _post(
    Uri url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
    } on Exception {
      throw const GuessException(
          "Couldn't reach the AI — check the connection (or that your local "
          'server is running).');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const GuessException(
          'The AI service refused the key — check it in Settings.');
    }
    if (res.statusCode != 200) {
      throw GuessException(
          'The AI service answered ${res.statusCode} — try again in a '
          'moment.');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const GuessException('The AI answered in an unexpected shape.');
    }
    return decoded;
  }
}
