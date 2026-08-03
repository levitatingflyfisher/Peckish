import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' show Format;
import 'package:peckish/features/barcode/presentation/scanner_tuning.dart';

// ReaderWidget needs a real camera, which this CI box does not have, so the
// decode settings live as plain consts and pinning them here is the only
// honest test. Each assertion is a phone-test lesson: v0.2 shipped the
// ReaderWidget defaults and "doesn't seem to auto recognize" was the verdict.
void main() {
  test('decoding works hard: harder/inverted/rotated/downscaled all on', () {
    expect(ScannerTuning.tryHarder, isTrue,
        reason: 'the v0.2 default (false) is tuned for QR posters, not '
            'curved glossy grocery labels');
    expect(ScannerTuning.tryInverted, isTrue);
    expect(ScannerTuning.tryRotate, isTrue);
    expect(ScannerTuning.tryDownscale, isTrue);
  });

  test('only 1D retail formats are decoded', () {
    expect(ScannerTuning.codeFormat, Format.linearCodes,
        reason: 'GTINs are 1D; scanning Format.any invites QR noise');
  });

  test('attempt cadence feels live, success pause covers the sheet', () {
    expect(ScannerTuning.scanDelay, const Duration(milliseconds: 400),
        reason: 'one attempt per second (the default) reads as a dead camera');
    expect(ScannerTuning.scanDelaySuccess, const Duration(milliseconds: 2000));
  });

  test('most of the frame is decoded, not just an invisible center square', () {
    expect(ScannerTuning.cropPercent, 0.75,
        reason: 'users cannot aim at a crop box they cannot see');
  });

  test('gallery and flash are offered; camera flip is not', () {
    expect(ScannerTuning.showGallery, isTrue,
        reason: 'a picked photo is the fallback when live decode never locks');
    expect(ScannerTuning.showFlashlight, isTrue);
    expect(ScannerTuning.showToggleCamera, isFalse,
        reason: 'nobody scans groceries with the selfie camera');
  });
}
