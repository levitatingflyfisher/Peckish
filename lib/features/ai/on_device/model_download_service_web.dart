import 'dart:async';

import 'package:peckish/features/ai/on_device/model_spec.dart';

/// Web build: no on-device runtime in the browser, so there is nothing to
/// download or manage. Every model reports "not downloaded" and a download
/// attempt fails cleanly. Touches no dart:io / path_provider / dio file
/// APIs, so it is safe in `flutter build web`.
class ModelDownloadService {
  ModelDownloadService();

  Future<bool> isDownloaded(PeckishModelSpec spec) async => false;

  Future<bool> hasPartial(PeckishModelSpec spec) async => false;

  Stream<(int, int)> download(PeckishModelSpec spec) => Stream.error(
        UnsupportedError(
            'On-device models are not available in the web version.'),
      );

  Future<void> delete(PeckishModelSpec spec) async {}
}
