import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/barcode_normalize.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// One downloaded barcode slice (ADR-0010): a read-only sqlite file with a
/// `products` table keyed by normalized barcode and a `meta` table carrying
/// its source/license/attribution. USDA and OFF slices are separate files by
/// law — this class reads exactly one of them and never writes.
class LocalBarcodeDb {
  /// Opening is lazy: constructing a handle for a path that is still
  /// downloading (or already deleted) costs nothing and cannot throw.
  LocalBarcodeDb(this.path);

  final String path;
  Database? _db;

  /// The file's identity when the handle opened. The twice-a-year refresh
  /// installs a NEW file under the SAME path; on POSIX an old fd would keep
  /// serving the unlinked inode forever, so a changed mtime/size reopens.
  FileStat? _openedStat;

  Database _open() {
    final stat = File(path).statSync();
    final opened = _openedStat;
    if (_db != null &&
        opened != null &&
        (stat.modified != opened.modified || stat.size != opened.size)) {
      close();
    }
    if (_db == null) {
      _openedStat = stat;
      _db = sqlite3.open(path, mode: OpenMode.readOnly);
    }
    return _db!;
  }

  /// The product for [code], or null when this slice doesn't know it.
  ///
  /// Throws when the file is gone or unreadable — the resolver treats that
  /// as a miss and drops the handle. The existence check matters: on POSIX
  /// a deleted file would otherwise keep serving stale rows through the old
  /// file descriptor.
  OffProduct? lookup(BarcodeCode code) {
    if (!File(path).existsSync()) {
      close();
      throw StateError('Barcode database is gone: $path');
    }
    final rows = _open().select(
      'SELECT name, brand, kcal, protein_g, carb_g, fat_g, '
      'serving_g, serving_label FROM products WHERE barcode = ?',
      [normalizeBarcode(code.value)],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final name = row['name'] as String;
    return OffProduct(
      barcode: code.value,
      // Same fallback as the network path: a nameless product shows its code.
      name: name.isEmpty ? code.value : name,
      brand: row['brand'] as String?,
      // Null stays null (unknown, never zero); clamped() zeroes the slightly
      // negative carb-by-difference lab artifacts USDA publishes.
      per100g: MacroSet(
        kcal: _toDouble(row['kcal']),
        proteinG: _toDouble(row['protein_g']),
        carbG: _toDouble(row['carb_g']),
        fatG: _toDouble(row['fat_g']),
      ).clamped(),
      servingLabel: row['serving_label'] as String?,
      servingGrams: _toDouble(row['serving_g']),
    );
  }

  /// The slice's `meta` table as a map — source, license, attribution,
  /// built_at — so the UI can show provenance and staleness.
  Map<String, String> meta() {
    final rows = _open().select('SELECT key, value FROM meta');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  void close() {
    _db?.dispose();
    _db = null;
  }

  /// REAL columns come back as double, but a builder that inserted a whole
  /// number may have stored an INTEGER — tolerate both.
  static double? _toDouble(Object? v) => (v as num?)?.toDouble();
}
