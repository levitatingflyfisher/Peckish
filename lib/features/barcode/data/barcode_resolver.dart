import 'package:peckish/features/barcode/data/local_barcode_db.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/food/domain/custom_food.dart';

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

/// The household already saved this code as one of its own foods. Beats
/// every slice: it is the answer the user chose, at the portion they chose,
/// and it costs no lookup at all.
class BarcodeSavedFood extends BarcodeResolution {
  BarcodeSavedFood(this.food);

  final CustomFood food;
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
  /// [savedFood] is the seam to the household's own foods — omit it and the
  /// resolver behaves exactly as it did before saved foods answered.
  BarcodeResolver({
    required Future<String?> Function(String dbId) installedDbPath,
    Future<CustomFood?> Function(BarcodeCode code)? savedFood,
  })  : _installedDbPath = installedDbPath,
        _savedFood = savedFood;

  final Future<String?> Function(String dbId) _installedDbPath;
  final Future<CustomFood?> Function(BarcodeCode code)? _savedFood;

  /// USDA first — CC0 and the default recommendation — then OFF.
  static const chain = ['usda', 'off_us'];

  /// Open handles per slice id, so a scan doesn't reopen the file every
  /// time. (LocalBarcodeDb itself reopens when the file is replaced under
  /// the same path — the refresh flow.)
  final _open = <String, LocalBarcodeDb>{};

  Future<BarcodeResolution> resolveLocal(BarcodeCode code) async {
    // Your own shelf first. A food you already saved off this package is
    // the most authoritative answer there is, and the cheapest — no file
    // opened, and certainly no network.
    if (_savedFood != null) {
      try {
        final mine = await _savedFood(code);
        if (mine != null) return BarcodeSavedFood(mine);
      } on Object {
        // A read that fails is "nothing saved", never a crash escaping to
        // the scan screen — the slices below can still answer.
      }
    }
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
