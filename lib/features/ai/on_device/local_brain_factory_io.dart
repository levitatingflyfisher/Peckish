import 'package:flutter/foundation.dart';

import 'package:peckish/features/ai/on_device/gemma_brain_io.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';

/// Whether THIS build can run a downloaded model. Android only — and
/// `debugDefaultTargetPlatformOverride` makes it testable on the VM.
bool get onDeviceLlmSupported =>
    defaultTargetPlatform == TargetPlatform.android;

/// The real brain. Construction is inert (nothing loads until the first
/// guess), so handing one out on an unsupported io platform is harmless —
/// the guess path answers with the calm not-downloaded line.
LocalBrain? createLocalBrain({
  required ModelDownloadService downloads,
  required String? Function() modelId,
}) =>
    GemmaLocalBrain(downloads: downloads, modelId: modelId);
