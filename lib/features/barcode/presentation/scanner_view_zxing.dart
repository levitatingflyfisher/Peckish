import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:peckish/features/barcode/presentation/scanner_tuning.dart';

/// The camera scanner (FLOSS zxing-cpp via FFI — no Google ML Kit blob).
/// Only Android/iOS have camera support in flutter_zxing; everywhere else
/// [available] is false and the screen shows manual entry alone.
class ScannerView extends StatelessWidget {
  const ScannerView({super.key, required this.onCode, this.onError});

  final void Function(String raw) onCode;

  /// Camera failed to start (permission, hardware, emulator). The screen
  /// falls back to typing — a scanner that silently shows black is worse.
  final void Function(Exception error)? onError;

  static bool get available =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    // All decode settings live in ScannerTuning (tested; this pass-through
    // cannot be, since ReaderWidget needs a real camera to build).
    return ReaderWidget(
      codeFormat: ScannerTuning.codeFormat,
      tryHarder: ScannerTuning.tryHarder,
      tryInverted: ScannerTuning.tryInverted,
      tryRotate: ScannerTuning.tryRotate,
      tryDownscale: ScannerTuning.tryDownscale,
      scanDelay: ScannerTuning.scanDelay,
      scanDelaySuccess: ScannerTuning.scanDelaySuccess,
      cropPercent: ScannerTuning.cropPercent,
      showGallery: ScannerTuning.showGallery,
      showFlashlight: ScannerTuning.showFlashlight,
      showToggleCamera: ScannerTuning.showToggleCamera,
      onControllerCreated: (_, error) {
        if (error != null) onError?.call(error);
      },
      onScan: (code) {
        final text = code.text;
        if (code.isValid && text != null && text.isNotEmpty) onCode(text);
      },
    );
  }
}
