import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/model_download_service_web.dart';

/// Web: no runtime, no brain — the settings radio never offers on-device
/// here, and the guess path answers with a calm platform line if a synced
/// config arrives pointing at it.
bool get onDeviceLlmSupported => false;

LocalBrain? createLocalBrain({
  required ModelDownloadService downloads,
  required String? Function() modelId,
}) =>
    null;
