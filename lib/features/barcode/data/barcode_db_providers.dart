import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/features/barcode/data/barcode_db_download_service.dart';

/// The platform-selected barcode-slice downloader (inert on web).
final barcodeDbDownloadServiceProvider =
    Provider<BarcodeDbDownloadService>((_) => BarcodeDbDownloadService());
