import 'package:peckish/features/barcode/data/local_barcode_db.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';

/// The answer of one local resolution pass. Sealed so the UI must handle
/// both shapes — there is no silent third outcome.
sealed class BarcodeResolution {}

/// A local slice knew the code.
class BarcodeHit extends BarcodeResolution {
  BarcodeHit({required this.product, required this.sourceId});

  final OffProduct product;

  /// Which slice answered: 'usda' | 'off_us'. The UI credits per source —
  /// ODbL wants attribution pinned to the OFF data (ADR-0010).
  final String sourceId;
}

/// No local slice knew the code. The network is a question the UI asks the
/// user, never something this layer touches.
class BarcodeMiss extends BarcodeResolution {
  BarcodeMiss({required this.anyLocalDb});

  /// True when at least one installed slice was actually consulted, so the
  /// miss screen can say "not in your offline database" instead of pointing
  /// at the download.
  final bool anyLocalDb;
}

/// ADR-0010's lookup chain: local USDA slice, then local OFF slice, first
/// hit wins. Each slice stays its own file (source-purity law); the chain
/// across them is the Collective Database that keeps ODbL obligations
/// pinned to the OFF file alone.
class BarcodeResolver {
  /// [installedDbPath] is the seam to the download service: the file path
  /// of an installed slice by id, or null when it isn't installed.
  BarcodeResolver({
    required Future<String?> Function(String dbId) installedDbPath,
  }) : _installedDbPath = installedDbPath;

  final Future<String?> Function(String dbId) _installedDbPath;

  /// USDA first — CC0 and the default recommendation — then OFF.
  static const chain = ['usda', 'off_us'];

  /// Open handles per slice id, so a scan doesn't reopen the file every
  /// time. (LocalBarcodeDb itself reopens when the file is replaced under
  /// the same path — the refresh flow.)
  final _open = <String, LocalBarcodeDb>{};

  Future<BarcodeResolution> resolveLocal(BarcodeCode code) async {
    var anyLocalDb = false;
    for (final id in chain) {
      // The seam does real file I/O and may throw mid-probe (the management
      // screen deleting in a race window): that's "not installed", never a
      // crash escaping to the scan screen.
      String? path;
      try {
        path = await _installedDbPath(id);
      } on Object {
        path = null;
      }
      if (path == null) {
        // Uninstalled: release the handle so the fd doesn't pin a deleted
        // file's bytes on disk.
        _open.remove(id)?.close();
        continue;
      }
      var db = _open[id];
      if (db != null && db.path != path) {
        db.close();
        _open.remove(id);
        db = null;
      }
      db ??= _open[id] = LocalBarcodeDb(path);
      try {
        final product = db.lookup(code);
        anyLocalDb = true;
        if (product != null) return BarcodeHit(product: product, sourceId: id);
      } on Object {
        // A deleted or corrupt file is a miss, never a crash. Dropping the
        // handle lets a fresh download at the same path open cleanly.
        db.close();
        _open.remove(id);
      }
    }
    return BarcodeMiss(anyLocalDb: anyLocalDb);
  }

  void close() {
    for (final db in _open.values) {
      db.close();
    }
    _open.clear();
  }
}
