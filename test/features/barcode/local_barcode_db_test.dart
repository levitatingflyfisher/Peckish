import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/features/barcode/data/local_barcode_db.dart';
import 'package:peckish/features/barcode/data/local_barcode_db_web.dart' as web;
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/barcode_normalize.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// The offline barcode slice reader (ADR-0010). These tests build REAL
// sqlite files — the dev VM links the native lib the same way the drift
// migration tests do — so what passes here is the exact read path the
// device runs.
void main() {
  group('normalizeBarcode', () {
    test('strips leading zeros so UPC-A and GTIN-14 padding collapse', () {
      expect(normalizeBarcode('00027000612323'), '27000612323');
      expect(normalizeBarcode('027000612323'), '27000612323');
    });

    test('leaves a code without leading zeros alone', () {
      expect(normalizeBarcode('4006381333931'), '4006381333931');
    });

    test('all-zeros input collapses to a single zero, not empty', () {
      expect(normalizeBarcode('0'), '0');
      expect(normalizeBarcode('00000000'), '0');
    });
  });

  group('LocalBarcodeDb (io)', () {
    late Directory tempDir;
    late LocalBarcodeDb db;

    // A checksum-valid UPC-A whose stored key is '27000612323'.
    final upcA = BarcodeCode.tryParse('027000612323')!;
    final gtin14 = BarcodeCode.tryParse('00027000612323')!;
    // A checksum-valid EAN-13 that is never inserted.
    final absent = BarcodeCode.tryParse('4006381333931')!;

    // Builds a slice file with the shared schema both sources use.
    String buildSlice(
      String name, {
      List<List<Object?>> products = const [],
      Map<String, String> meta = const {},
    }) {
      final path = p.join(tempDir.path, name);
      final raw = sql.sqlite3.open(path);
      raw.execute(
          'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      raw.execute('CREATE TABLE products('
          'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, '
          'kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL, '
          'serving_g REAL, serving_label TEXT)');
      for (final e in meta.entries) {
        raw.execute('INSERT INTO meta VALUES (?, ?)', [e.key, e.value]);
      }
      for (final row in products) {
        raw.execute(
            'INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', row);
      }
      raw.dispose();
      return path;
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('peckish_barcode_db');
    });

    tearDown(() {
      db.close();
      tempDir.deleteSync(recursive: true);
    });

    test('a hit maps every column onto OffProduct', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        [
          '27000612323',
          'Chocolate Chips',
          'Toll House',
          480.0,
          4.0,
          62.0,
          24.0,
          14.0,
          '1 tbsp (14 g)',
        ],
      ]));

      final product = db.lookup(upcA)!;
      expect(product.name, 'Chocolate Chips');
      expect(product.brand, 'Toll House');
      expect(product.per100g.kcal, 480);
      expect(product.per100g.proteinG, 4);
      expect(product.per100g.carbG, 62);
      expect(product.per100g.fatG, 24);
      expect(product.servingGrams, 14);
      expect(product.servingLabel, '1 tbsp (14 g)');
    });

    test('the same product answers its zero-padded GTIN-14 form', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        ['27000612323', 'Chocolate Chips', null, 480.0, null, null, null, null, null],
      ]));

      expect(db.lookup(gtin14)?.name, 'Chocolate Chips');
    });

    test('unknown macros stay null — never zero', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        ['27000612323', 'Mystery Snack', null, null, null, null, null, null, null],
      ]));

      final product = db.lookup(upcA)!;
      expect(product.per100g.kcal, isNull);
      expect(product.per100g.proteinG, isNull);
      expect(product.per100g.carbG, isNull);
      expect(product.per100g.fatG, isNull);
      expect(product.servingGrams, isNull);
      expect(product.servingLabel, isNull);
    });

    test('negative lab artifacts are clamped to zero on the way out', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        ['27000612323', 'Diet Soda', null, 0.0, 0.0, -0.4, 0.0, null, null],
      ]));

      expect(db.lookup(upcA)!.per100g.carbG, 0);
    });

    test('an empty stored name falls back to the scanned barcode', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        ['27000612323', '', null, null, null, null, null, null, null],
      ]));

      expect(db.lookup(upcA)!.name, '027000612323');
    });

    test('a barcode not in the slice is a null miss', () {
      db = LocalBarcodeDb(buildSlice('usda.db', products: [
        ['27000612323', 'Chocolate Chips', null, null, null, null, null, null, null],
      ]));

      expect(db.lookup(absent), isNull);
    });

    test('meta() returns the meta table verbatim', () {
      db = LocalBarcodeDb(buildSlice('off.db', meta: {
        'format_version': '1',
        'source': 'off_us',
        'license': 'ODbL-1.0',
        'attribution': 'Open Food Facts contributors',
      }));

      expect(db.meta(), {
        'format_version': '1',
        'source': 'off_us',
        'license': 'ODbL-1.0',
        'attribution': 'Open Food Facts contributors',
      });
    });

    test('a slice replaced at the same path serves the new data', () {
      // The twice-a-year refresh installs a NEW file under the SAME name
      // (delete → download → rename). A held sqlite fd would keep reading
      // the unlinked old inode on POSIX — the handle must notice the file
      // changed underneath it and reopen.
      final path = buildSlice('usda.db', products: [
        ['27000612323', 'Old Vintage Granola', null, 480.0, null, null, null, null, null],
      ]);
      db = LocalBarcodeDb(path);
      expect(db.lookup(upcA)!.name, 'Old Vintage Granola');

      File(path).deleteSync();
      buildSlice('usda.db', products: [
        ['27000612323', 'New Granola', null, 500.0, null, null, null, null, null],
      ]);

      expect(db.lookup(upcA)!.name, 'New Granola');
      expect(db.lookup(upcA)!.per100g.kcal, 500.0);
    });
  });

  group('LocalBarcodeDb (web)', () {
    test('never answers and never throws', () {
      final stub = web.LocalBarcodeDb('/nowhere/usda.db');
      expect(stub.lookup(BarcodeCode.tryParse('027000612323')!), isNull);
      expect(stub.meta(), isEmpty);
      stub.close();
    });
  });
}
