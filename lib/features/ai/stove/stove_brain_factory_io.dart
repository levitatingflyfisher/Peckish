import 'package:dio/dio.dart';
import 'package:domovoi/domovoi.dart';

import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/stove/stove_brain.dart';

/// Any io platform can reach a stove on the LAN; only web bows out (its
/// https origin cannot call a plain-http LAN host anyway).
bool get stoveSupported => true;

/// Settings-time phrase validation, through the SAME derivation the ask
/// path uses ([DomovoiKeys]) — null when fine, a calm line when not.
Future<String?> stovePhraseProblem(String phrase) async {
  try {
    await DomovoiKeys.seedFromPhrase(phrase);
    return null;
  } catch (_) {
    return "That doesn't look like a household phrase — check the words "
        'and their order (it has a built-in spell check).';
  }
}

/// The real thing. Construction is inert (nothing is derived or contacted
/// until the first guess); incomplete config answers at ask time with a
/// calm, actionable line.
StoveBrain? createStoveBrain(AiConfig config, {Dio? dio}) =>
    _DomovoiStoveBrain(config, dio);

class _DomovoiStoveBrain implements StoveBrain {
  _DomovoiStoveBrain(this._config, this._dio);

  final AiConfig _config;
  final Dio? _dio;

  @override
  Future<String> complete(String prompt) async {
    final host = _config.stoveHost;
    final phrase = _config.stovePhrase;
    if (host == null || host.isEmpty || phrase == null || phrase.isEmpty) {
      throw const GuessException(
          "The stove isn't set up yet — add its address and the household "
          'phrase in Settings.');
    }
    final client = StoveClient(
      host: host,
      port: _config.stovePort ?? AiConfig.defaultStovePort,
      // The seed, not the stove key: StoveClient derives its own key under
      // the stove HKDF domain, so the stove only ever learns its own key.
      secret: () => DomovoiKeys.seedFromPhrase(phrase),
      dio: _dio,
    );
    try {
      return await client.complete(prompt);
    } on AskException catch (e) {
      // domovoi's messages are already written for people; keep them.
      throw GuessException(e.message);
    } on Exception {
      // An invalid stored phrase surfaces from seed derivation itself.
      throw const GuessException(
          "The stove couldn't be asked — check the household phrase in "
          'Settings.');
    }
  }
}
