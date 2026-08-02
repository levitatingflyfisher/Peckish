import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/features/barcode/data/barcode_resolver.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// The local resolution chain (ADR-0010): USDA slice, then the OFF slice,
// first hit wins, and a miss never touches the network by itself. The
// installedDbPath seam stands in for the download service.
void main() {
  late Directory tempDir;
  final code = BarcodeCode.tryParse('027000612323')!;

  // Builds a slice file at [name] holding one product under the key
  // '27000612323', named per source so chain order is observable.
  String buildSlice(String name, String productName) {
    final path = p.join(tempDir.path, name);
    final raw = sql.sqlite3.open(path);
    raw.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    raw.execute('CREATE TABLE products('
        'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, '
        'kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL, '
        'serving_g REAL, serving_label TEXT)');
    raw.execute('INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['27000612323', productName, null, 480.0, null, null, null, null, null]);
    raw.dispose();
    return path;
  }

  // An empty slice: valid schema, no products.
  String buildEmptySlice(String name) {
    final path = p.join(tempDir.path, name);
    final raw = sql.sqlite3.open(path);
    raw.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    raw.execute('CREATE TABLE products('
        'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, '
        'kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL, '
        'serving_g REAL, serving_label TEXT)');
    raw.dispose();
    return path;
  }

  BarcodeResolver resolverWith(Map<String, String> installed) {
    return BarcodeResolver(
      installedDbPath: (dbId) async => installed[dbId],
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('peckish_barcode_resolver');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('a USDA hit wins even when the OFF slice also knows the code', () async {
    final resolver = resolverWith({
      'usda': buildSlice('usda.db', 'From USDA'),
      'off_us': buildSlice('off.db', 'From OFF'),
    });

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeHit;
    expect(resolution.sourceId, 'usda');
    expect(resolution.product.name, 'From USDA');
    resolver.close();
  });

  test('a USDA miss falls through to the OFF slice', () async {
    final resolver = resolverWith({
      'usda': buildEmptySlice('usda.db'),
      'off_us': buildSlice('off.db', 'From OFF'),
    });

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeHit;
    expect(resolution.sourceId, 'off_us');
    expect(resolution.product.name, 'From OFF');
    resolver.close();
  });

  test('no installed slices → miss that says so', () async {
    final resolver = resolverWith(const {});

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeMiss;
    expect(resolution.anyLocalDb, isFalse);
    resolver.close();
  });

  test('installed slices without the code → miss that a lookup ran',
      () async {
    final resolver = resolverWith({'usda': buildEmptySlice('usda.db')});

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeMiss;
    expect(resolution.anyLocalDb, isTrue);
    resolver.close();
  });

  test('a slice file deleted after a hit becomes a miss, not a crash',
      () async {
    final path = buildSlice('usda.db', 'From USDA');
    final resolver = resolverWith({'usda': path});

    expect(await resolver.resolveLocal(code), isA<BarcodeHit>());

    File(path).deleteSync();
    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeMiss;
    expect(resolution.anyLocalDb, isFalse);
    resolver.close();
  });

  test('a fresh download at the same path is picked up after deletion',
      () async {
    final path = buildSlice('usda.db', 'First download');
    final resolver = resolverWith({'usda': path});
    expect(await resolver.resolveLocal(code), isA<BarcodeHit>());

    // Delete, resolve (drops the stale handle), then re-download in place.
    File(path).deleteSync();
    expect(await resolver.resolveLocal(code), isA<BarcodeMiss>());
    buildSlice('usda.db', 'Second download');

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeHit;
    expect(resolution.product.name, 'Second download');
    resolver.close();
  });

  test('a corrupt slice file is a miss, not a crash', () async {
    final path = p.join(tempDir.path, 'usda.db');
    File(path).writeAsStringSync('this is not a sqlite database at all');
    final resolver = resolverWith({'usda': path});

    final resolution = await resolver.resolveLocal(code);
    resolution as BarcodeMiss;
    expect(resolution.anyLocalDb, isFalse);
    resolver.close();
  });
}
