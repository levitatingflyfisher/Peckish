import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// The camera scanner (FLOSS zxing-cpp via FFI — no Google ML Kit blob).
/// Only Android/iOS have camera support in flutter_zxing; everywhere else
/// [available] is false and the screen shows manual entry alone.
class ScannerView extends StatelessWidget {
  const ScannerView({super.key, required this.onCode});

  final void Function(String raw) onCode;

  static bool get available =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    return ReaderWidget(
      codeFormat: Format.any,
      showGallery: false,
      tryInverted: true,
      onScan: (code) {
        final text = code.text;
        if (code.isValid && text != null && text.isNotEmpty) onCode(text);
      },
    );
  }
}
