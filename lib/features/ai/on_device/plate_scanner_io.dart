import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'package:peckish/features/ai/on_device/plate_scan.dart';

/// Whether THIS build can label a plate photo: ML Kit's bundled classifier
/// is Android-only here. `debugDefaultTargetPlatformOverride` makes the
/// flag testable on the VM.
bool get plateScanSupported =>
    defaultTargetPlatform == TargetPlatform.android;

/// The rung-1 gateway: one photo in, the classifier's sightings out.
/// A fresh labeler per call, closed in `finally` — the base model lives in
/// Play Services, so there is nothing heavy to keep resident.
class PlateScanner {
  Future<List<DetectedLabel>> labelsOf(String imagePath) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(
          confidenceThreshold: PlateScan.noiseFloor),
    );
    try {
      final labels =
          await labeler.processImage(InputImage.fromFilePath(imagePath));
      return [
        for (final l in labels)
          (label: l.label, confidence: l.confidence),
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
