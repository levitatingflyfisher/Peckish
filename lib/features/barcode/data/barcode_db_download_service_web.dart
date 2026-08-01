import 'dart:async';

import 'package:peckish/features/barcode/data/barcode_db_spec.dart';

/// The browser holds no slice files. The seam owns the answer so screens
/// gate on capability, never on `kIsWeb` (the house trio idiom).
bool get localSlicesSupported => false;

/// Web build: no local slices in the browser (ADR-0010 — web stays
/// online-only), so there is nothing to download or manage. Every slice
/// reports "not installed" and a download attempt fails cleanly. Touches
/// no dart:io / path_provider / dio file APIs, so it is safe in
/// `flutter build web`.
class BarcodeDbDownloadService {
  BarcodeDbDownloadService();

  Future<bool> isInstalled(BarcodeDbSpec spec) async => false;

  Future<bool> hasPartial(BarcodeDbSpec spec) async => false;

  Future<String?> installedDbPath(String id) async => null;

  Stream<(int, int)> download(BarcodeDbSpec spec) => Stream.error(
        UnsupportedError(
            'Offline barcode databases are not available in the web version.'),
      );

  Future<void> delete(BarcodeDbSpec spec) async {}
}
