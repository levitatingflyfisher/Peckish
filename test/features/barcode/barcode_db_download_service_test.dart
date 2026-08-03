import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/features/barcode/data/barcode_db_download_service.dart';
import 'package:peckish/features/barcode/data/barcode_db_spec.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// In-memory dio transport (the Reckon/model-service harness): `flutter
/// test` stubs `HttpClient` to fail every real request, so we swap dio's
/// adapter for one serving bytes from memory — the REAL download/append/
/// deleteOnError logic still runs, and Range (206) is honoured like a CDN.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.payload, {this.ignoreRange = false, this.errorStatus});

  final List<int> payload;
  final bool ignoreRange;
  final int? errorStatus;
  final List<String?> rangeHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final range =
        (options.headers['Range'] ?? options.headers['range'])?.toString();
    rangeHeaders.add(range);

    if (errorStatus != null) {
      return ResponseBody.fromBytes(Uint8List(0), errorStatus!);
    }

    var start = 0;
    var status = HttpStatus.ok;
    final headers = <String, List<String>>{};
    if (!ignoreRange && range != null && range.startsWith('bytes=')) {
      start = int.parse(range.substring('bytes='.length).split('-').first);
      if (start > payload.length) {
        return ResponseBody.fromBytes(
            Uint8List(0), HttpStatus.requestedRangeNotSatisfiable);
      }
      status = HttpStatus.partialContent;
      headers[HttpHeaders.contentRangeHeader] = [
        'bytes $start-${payload.length - 1}/${payload.length}'
      ];
    }
    final body = Uint8List.fromList(payload.sublist(start));
    headers[HttpHeaders.contentLengthHeader] = ['${body.length}'];
    return ResponseBody.fromBytes(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;

  /// A tiny REAL sqlite slice in the shipped schema, gzipped and hashed in
  /// setUp — so the sha-check → gunzip → install pipeline is exercised
  /// end-to-end on genuine bytes, not stand-ins.
  late List<int> dbBytes;
  late List<int> gzBytes;
  late String gzSha;
  late BarcodeDbSpec spec;

  BarcodeDbSpec specWith({String? sha}) => BarcodeDbSpec(
        id: 'test_slice',
        displayName: 'Test slice',
        downloadUrl: 'https://example.test/test.sqlite.gz',
        fileName: 'barcodes_test_v1.sqlite',
        sha256Gz: sha ?? gzSha,
        licenseName: 'CC0 1.0',
        licenseUrl: 'https://example.test/license',
        attribution: 'Test data.',
        approxBytes: 0,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peckish_barcode_db_test');
    final source = File(p.join(tempDir.path, 'source.sqlite'));
    final db = sq.sqlite3.open(source.path);
    db.execute('''
      CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE products(
        barcode TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL,
        serving_g REAL, serving_label TEXT);
      INSERT INTO meta VALUES('format_version','1');
      INSERT INTO products(barcode, name, kcal)
        VALUES('12345678905','Test Bar', 390);
    ''');
    db.dispose();
    dbBytes = await source.readAsBytes();
    await source.delete();
    gzBytes = gzip.encode(dbBytes);
    gzSha = sha256.convert(gzBytes).toString();
    spec = specWith();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  ({BarcodeDbDownloadService svc, _FakeAdapter adapter}) build({
    bool ignoreRange = false,
    int? errorStatus,
  }) {
    final adapter = _FakeAdapter(gzBytes,
        ignoreRange: ignoreRange, errorStatus: errorStatus);
    final dio = Dio()..httpClientAdapter = adapter;
    return (
      svc: BarcodeDbDownloadService(
        dio: dio,
        supportDirectory: () async => tempDir,
        // The real catalog plus the test slice, so installedDbPath can
        // resolve both.
        catalog: [spec, ...barcodeDbCatalog],
      ),
      adapter: adapter,
    );
  }

  // Reference data lives under <support>/barcode_dbs/, never documents.
  File installed(String fileName) =>
      File(p.join(tempDir.path, 'barcode_dbs', fileName));
  File gzOf() => installed('${spec.fileName}.gz');
  File gzPartOf() => installed('${spec.fileName}.gz.part');
  File dbPartOf() => installed('${spec.fileName}.part');
  File dbOf() => installed(spec.fileName);

  Future<void> seed(File f, List<int> bytes) async {
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  test(
      'native builds support local slices (the capability seam answers, '
      'screens never ask kIsWeb)', () {
    expect(localSlicesSupported, isTrue);
  });

  test('isInstalled is false when nothing is on disk', () async {
    final h = build();
    expect(await h.svc.isInstalled(spec), isFalse);
  });

  test('isInstalled rejects (and removes) a garbage final file', () async {
    await seed(dbOf(), 'not a database at all'.codeUnits);
    final h = build();
    expect(await h.svc.isInstalled(spec), isFalse);
    expect(dbOf().existsSync(), isFalse,
        reason: 'junk at the final path is cleared, never trusted');
  });

  test('a fresh download installs the slice end-to-end', () async {
    final h = build();

    final events = await h.svc.download(spec).toList();

    expect(await dbOf().readAsBytes(), dbBytes,
        reason: 'installed file must be the gunzipped payload byte-for-byte');
    expect(await h.svc.isInstalled(spec), isTrue);
    expect(gzOf().existsSync(), isFalse,
        reason: 'the compressed artifact is cleaned up after install');
    expect(gzPartOf().existsSync(), isFalse);
    expect(dbPartOf().existsSync(), isFalse);
    expect(h.adapter.rangeHeaders, [null],
        reason: 'no .gz.part yet, so no Range header');
    expect(events.last, (gzBytes.length, gzBytes.length));
  });

  test('installedDbPath resolves an installed catalog slice, else null',
      () async {
    final h = build();
    final usda = barcodeDbCatalog.firstWhere((s) => s.id == 'usda');

    expect(await h.svc.installedDbPath('usda'), isNull);

    // Real sqlite bytes at the final path IS installed (rename is the only
    // route there in production; tests place them directly).
    await seed(installed(usda.fileName), dbBytes);

    expect(await h.svc.installedDbPath('usda'), installed(usda.fileName).path);
    expect(await h.svc.installedDbPath('off_us'), isNull);
    expect(await h.svc.installedDbPath('no_such_slice'), isNull);
  });

  test('an existing .gz.part resumes with a Range request', () async {
    final have = gzBytes.length ~/ 2;
    await seed(gzPartOf(), gzBytes.sublist(0, have));
    final h = build();

    await h.svc.download(spec).toList();

    expect(h.adapter.rangeHeaders, ['bytes=$have-']);
    expect(await dbOf().readAsBytes(), dbBytes,
        reason: 'resumed transfer must still gunzip to the exact payload');
  });

  test('an oversized .gz.part (416) restarts cleanly from zero', () async {
    await seed(gzPartOf(), Uint8List(gzBytes.length + 1024));
    final h = build();

    await h.svc.download(spec).toList();

    expect(await dbOf().readAsBytes(), dbBytes);
  });

  test('a host that ignores Range (200) restarts instead of appending',
      () async {
    await seed(gzPartOf(), List<int>.filled(64, 0xFF));
    final h = build(ignoreRange: true);

    await h.svc.download(spec).toList();

    expect(await dbOf().readAsBytes(), dbBytes,
        reason: 'a 200 must overwrite the .gz.part, never append onto it');
  });

  test('a sha mismatch deletes the .gz and throws the typed exception',
      () async {
    final wrong = specWith(sha: 'a' * 64);
    final h = build();

    await expectLater(h.svc.download(wrong).toList(),
        throwsA(isA<BarcodeDbIntegrityException>()));

    expect(gzOf().existsSync(), isFalse,
        reason: 'corrupt bytes are removed — nothing survives to resume');
    expect(gzPartOf().existsSync(), isFalse);
    expect(await h.svc.isInstalled(wrong), isFalse);
  });

  test('a PENDING sha fails closed before any network', () async {
    final pending = specWith(sha: 'PENDING');
    final h = build();

    await expectLater(
        h.svc.download(pending).toList(), throwsA(isA<StateError>()));

    expect(h.adapter.rangeHeaders, isEmpty,
        reason: 'a catalog entry without a hash must never hit the network');
  });

  test('hasPartial reports an orphaned verified-.gz awaiting install',
      () async {
    final h = build();
    // A completed transfer killed before verify/gunzip leaves a full .gz —
    // the UI must offer Resume, not pretend nothing happened.
    await seed(gzOf(), gzBytes);
    expect(await h.svc.hasPartial(spec), isTrue);
  });

  test('a complete orphaned .gz installs with zero network requests', () async {
    await seed(gzOf(), gzBytes);
    // A stale .gz.part alongside must not survive to poison a later resume.
    await seed(gzPartOf(), gzBytes.sublist(0, 64));
    final h = build();

    final events = await h.svc.download(spec).toList();

    expect(h.adapter.rangeHeaders, isEmpty,
        reason: 'the bytes are already here — the network owes us nothing');
    expect(await dbOf().readAsBytes(), dbBytes);
    expect(await h.svc.isInstalled(spec), isTrue);
    expect(gzOf().existsSync(), isFalse);
    expect(gzPartOf().existsSync(), isFalse);
    expect(events, [(gzBytes.length, gzBytes.length)]);
  });

  test(
      'a sha-failing orphaned .gz is deleted and the normal transfer '
      'proceeds', () async {
    await seed(gzOf(), List<int>.from(gzBytes)..[0] ^= 0xFF);
    final h = build();

    await h.svc.download(spec).toList();

    expect(h.adapter.rangeHeaders, [null],
        reason: 'the corrupt orphan is discarded and the wire does the job');
    expect(await dbOf().readAsBytes(), dbBytes);
    expect(await h.svc.isInstalled(spec), isTrue);
  });

  test('hasPartial is true only mid-transfer', () async {
    final h = build(errorStatus: 503);
    expect(await h.svc.hasPartial(spec), isFalse);

    // An interrupted transfer keeps its .gz.part — that IS the partial.
    await seed(gzPartOf(), gzBytes.sublist(0, 64));
    await expectLater(h.svc.download(spec).toList(), throwsA(isA<Object>()));
    expect(await h.svc.hasPartial(spec), isTrue);

    final ok = build();
    await ok.svc.download(spec).toList();
    expect(await ok.svc.hasPartial(spec), isFalse,
        reason: 'an installed slice outranks any leftover partial');
  });

  test('delete removes the slice and every intermediate', () async {
    await seed(dbOf(), dbBytes);
    await seed(gzOf(), gzBytes);
    await seed(gzPartOf(), gzBytes.sublist(0, 64));
    await seed(dbPartOf(), dbBytes.sublist(0, 64));
    final h = build();

    await h.svc.delete(spec);

    expect(dbOf().existsSync(), isFalse);
    expect(gzOf().existsSync(), isFalse);
    expect(gzPartOf().existsSync(), isFalse);
    expect(dbPartOf().existsSync(), isFalse);
  });

  test('the installed slice is a queryable database in the shipped schema',
      () async {
    final h = build();
    await h.svc.download(spec).toList();

    final db = sq.sqlite3.open((await h.svc.installedDbPath('test_slice'))!);
    addTearDown(db.dispose);
    final row = db.select('SELECT name, kcal FROM products WHERE barcode = ?',
        ['12345678905']).single;
    expect(row['name'], 'Test Bar');
    expect(row['kcal'], 390);
  });
}
