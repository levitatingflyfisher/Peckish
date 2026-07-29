import 'package:flutter/widgets.dart';

/// The no-camera build (web): scanning happens by typing the digits.
class ScannerView extends StatelessWidget {
  const ScannerView({super.key, required this.onCode, this.onError});

  final void Function(String raw) onCode;

  /// Never fires here — there is no camera to fail. Mirrors the zxing
  /// variant so callers compile against one shape.
  final void Function(Exception error)? onError;

  /// Whether this platform can point a camera at the bars.
  static bool get available => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
