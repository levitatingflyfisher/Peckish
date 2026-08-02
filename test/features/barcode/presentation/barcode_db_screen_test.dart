import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/features/barcode/data/barcode_db_download_service.dart';
import 'package:peckish/features/barcode/data/barcode_db_providers.dart';
import 'package:peckish/features/barcode/data/barcode_db_spec.dart';
import 'package:peckish/features/barcode/presentation/barcode_db_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Stands in for the real downloader: installed/paused states are declared
/// by the test, and installed paths point at REAL slice files so the
/// screen's meta read is the exact device path.
class _FakeDbService extends BarcodeDbDownloadService {
  _FakeDbService({
    Map<String, String> installedPaths = const {},
    Set<String> partials = const {},
  })  : _installedPaths = Map.of(installedPaths),
        _partials = Set.of(partials);

  final Map<String, String> _installedPaths;
  final Set<String> _partials;
  final deleted = <String>[];

  @override
  Future<bool> isInstalled(BarcodeDbSpec spec) async =>
      _installedPaths.containsKey(spec.id);

  @override
  Future<bool> hasPartial(BarcodeDbSpec spec) async =>
      _partials.contains(spec.id);

  @override
  Future<String?> installedDbPath(String id) async => _installedPaths[id];

  @override
  Stream<(int, int)> download(BarcodeDbSpec spec) => const Stream.empty();

  @override
  Future<void> delete(BarcodeDbSpec spec) async {
    deleted.add(spec.id);
    _installedPaths.remove(spec.id);
    _partials.remove(spec.id);
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('peckish_barcode_screen');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  // Builds a real slice carrying the meta the screen reads.
  String buildSlice(String name, Map<String, String> meta) {
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
    raw.dispose();
    return path;
  }

  Widget host(_FakeDbService service) => ProviderScope(
        overrides: [
          barcodeDbDownloadServiceProvider.overrideWithValue(service),
        ],
        child:
            MaterialApp(theme: AppTheme.light, home: const BarcodeDbScreen()),
      );

  testWidgets('the catalog renders one card per slice, plus the license '
      'truth in plain text', (tester) async {
    await tester.pumpWidget(host(_FakeDbService()));
    await tester.pumpAndSettle();

    expect(find.text('Offline barcode lookup'), findsOneWidget);
    // Titles carry the measured size once the integrator fills approxBytes,
    // so match on the name (it also anchors the footer's license line).
    expect(find.textContaining('US packaged foods (USDA)'), findsWidgets);
    expect(find.textContaining('Open Food Facts (US slice)'), findsWidgets);
    expect(find.text('Download'), findsNWidgets(2));
    // Attribution travels with each database — shown where it is offered.
    expect(find.textContaining('U.S. Department of Agriculture'),
        findsOneWidget);
    expect(find.textContaining('Contains information from Open Food Facts'),
        findsOneWidget);
    expect(find.textContaining('CC0 1.0'), findsOneWidget);
    expect(find.textContaining('opendatacommons.org'), findsOneWidget);
    // The source-purity law, said out loud.
    expect(find.textContaining('stay separate'), findsOneWidget);
  });

  testWidgets('an installed slice shows its product count and build date',
      (tester) async {
    final path = buildSlice('usda.db', {
      'format_version': '1',
      'source': 'usda',
      'product_count': '1934204',
      'built_at': '2025-12-18',
    });
    await tester.pumpWidget(
        host(_FakeDbService(installedPaths: {'usda': path})));
    await tester.pumpAndSettle();

    expect(find.textContaining('1934204 products'), findsOneWidget);
    expect(find.textContaining('2025-12-18'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    // The other slice still just offers Download.
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a half-finished download is paused, and Resume picks it up',
      (tester) async {
    await tester.pumpWidget(host(_FakeDbService(partials: {'usda'})));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('delete confirms first, then frees the slice', (tester) async {
    final path = buildSlice('usda.db', {'product_count': '10'});
    final service = _FakeDbService(installedPaths: {'usda': path});
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(service.deleted, isEmpty,
        reason: 'nothing is deleted before the user confirms');

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.deleted, ['usda']);
    expect(find.text('Download'), findsNWidgets(2),
        reason: 'the freed slice offers Download again');
  });
}
