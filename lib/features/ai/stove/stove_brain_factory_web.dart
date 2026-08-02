import 'package:dio/dio.dart';

import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/stove/stove_brain.dart';

/// Web: no stove — the settings radio never offers it here (an https page
/// cannot call a plain-http LAN host), and the guess path answers with a
/// calm platform line if a config arrives pointing at it.
bool get stoveSupported => false;

/// Unreachable while [stoveSupported] is false; answered honestly anyway.
Future<String?> stovePhraseProblem(String phrase) async =>
    'The stove is not available in the browser.';

StoveBrain? createStoveBrain(AiConfig config, {Dio? dio}) => null;
