import 'package:flutter_zxing/flutter_zxing.dart' show Format;

/// Decode settings for the camera scanner, kept as plain consts so they can
/// be pinned by tests on a camera-less CI box (ReaderWidget itself needs
/// real hardware to even build).
///
/// v0.2 shipped ReaderWidget's defaults and the phone-test verdict was
/// "doesn't seem to auto recognize": tryHarder off, only the invisible
/// center half of the frame decoded, one attempt per second. These settings
/// trade a little battery for reading the label on the first hold.
abstract final class ScannerTuning {
  /// More CPU per frame — grocery labels are curved, glossy, and dim.
  static const bool tryHarder = true;

  /// White-bars-on-dark packaging.
  static const bool tryInverted = true;

  /// Sideways phone or sideways package both read.
  static const bool tryRotate = true;

  /// Also try a downscaled frame; helps while the lens is focus-hunting.
  static const bool tryDownscale = true;

  /// Retail GTINs are 1D — excluding QR and friends removes false hits.
  static const int codeFormat = Format.linearCodes;

  /// Attempt cadence. One try per second (the default) reads as a dead
  /// camera; 400 ms feels continuous.
  static const Duration scanDelay = Duration(milliseconds: 400);

  /// Pause after a hit so the just-opened sheet is not instantly re-fired.
  static const Duration scanDelaySuccess = Duration(milliseconds: 2000);

  /// Decode 75% of the frame, not the default center half — users cannot
  /// aim at a crop box they cannot see.
  static const double cropPercent = 0.75;

  /// Photo-pick fallback (bundled with flutter_zxing, no new permission):
  /// decode a still photo when live decode never locks on.
  static const bool showGallery = true;

  static const bool showFlashlight = true;

  /// Nobody scans groceries with the selfie camera.
  static const bool showToggleCamera = false;
}
