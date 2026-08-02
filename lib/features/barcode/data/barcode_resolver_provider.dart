import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/barcode/data/barcode_db_providers.dart';
import 'package:peckish/features/barcode/data/barcode_resolver.dart';

/// One resolver for the app, wired to the household's own saved foods and
/// to the download service's "what is installed?" question; overridable in
/// tests.
final barcodeResolverProvider = Provider<BarcodeResolver>((ref) {
  final resolver = BarcodeResolver(
    savedFood: (code) =>
        ref.read(customFoodRepositoryProvider).byBarcode(code.value),
    installedDbPath: (id) =>
        ref.read(barcodeDbDownloadServiceProvider).installedDbPath(id),
  );
  ref.onDispose(resolver.close);
  return resolver;
});
