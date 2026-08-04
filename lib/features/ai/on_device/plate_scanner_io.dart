import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'package:peckish/features/ai/on_device/plate_scan.dart';

/// Whether THIS build can label a plate photo: ML Kit's bundled classifier
/// is Android-only here. `debugDefaultTargetPlatformOverride` makes the
/// flag testable on the VM.
bool get plateScanSupported => defaultTargetPlatform == TargetPlatform.android;

/// The rung-1 gateway: one photo in, the classifier's sightings out.
/// A fresh labeler per call, closed in `finally` — the model is BUNDLED
/// into the APK (the merged manifest registers `BundledLabelRegistrar`),
/// so there is no download to wait on and nothing heavy to keep resident.
///
/// Its ceiling is low and worth knowing: the base labeler is a general
/// scene classifier with roughly nineteen edible things among its 430
/// labels, so on most plates the best it can say is "Food". See
/// [PlateScan.genericFoodLabels].
class PlateScanner {
  Future<List<DetectedLabel>> labelsOf(String imagePath) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: PlateScan.noiseFloor),
    );
    try {
      final labels =
          await labeler.processImage(InputImage.fromFilePath(imagePath));
      return [
        for (final l in labels) (label: l.label, confidence: l.confidence),
      ];
    } on PlatformException {
      // ML Kit rides Google Play services; on a de-Googled phone the
      // channel answers with a platform error. Name it, typed.
      throw const PlateUnavailableException();
    } on MissingPluginException {
      // An absent channel (stripped build, no native registration) is the
      // same story for the user — the de-Googled explanation, not the
      // generic failure line.
      throw const PlateUnavailableException();
    } finally {
      await labeler.close();
    }
  }
}

PlateScanner? createPlateScanner() => PlateScanner();
