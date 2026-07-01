import 'package:peckish/features/ai/on_device/plate_scan.dart';

/// Web: no ML Kit, no plate scanning — the photo button never renders.
bool get plateScanSupported => false;

class PlateScanner {
  Future<List<DetectedLabel>> labelsOf(String imagePath) async => const [];
}

PlateScanner? createPlateScanner() => null;
