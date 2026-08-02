import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/model_spec.dart';

/// In-memory dio transport (the Reckon harness): `flutter test` stubs
/// `HttpClient` to fail every real request, so we swap dio's adapter for
/// one serving bytes from memory — the REAL download/append/deleteOnError
/// logic still runs, and Range (206) is honoured like a real CDN.
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
  late ModelDownloadService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peckish_model_test');
    service = ModelDownloadService(documentsDirectory: () async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  const spec = PeckishModelSpec.qwen05;

  File finalFile() => File('${tempDir.path}/${spec.fileName}');

  Future<void> writeBytes(File f, int bytes) async {
    await f.writeAsBytes(Uint8List(bytes));
  }

  test('isDownloaded is false when no file exists', () async {
    expect(await service.isDownloaded(spec), isFalse);
  });

  test(
      'a present final file counts as downloaded regardless of the declared '
      'approximate size (the Reckon scar: never delete real models)',
      () async {
    await writeBytes(finalFile(), 2 * 1024 * 1024);
    expect(await service.isDownloaded(spec), isTrue);
    expect(finalFile().existsSync(), isTrue);
  });

  test('isDownloaded deletes and rejects a sub-1MB junk file', () async {
    await writeBytes(finalFile(), 1024);
    expect(await service.isDownloaded(spec), isFalse);
    expect(finalFile().existsSync(), isFalse);
  });

  test('hasPartial reports a resumable half-download honestly', () async {
    expect(await service.hasPartial(spec), isFalse);
    final part = File('${tempDir.path}/${spec.fileName}.part');
    await writeBytes(part, 1024 * 1024);
    expect(await service.hasPartial(spec), isTrue);
    await writeBytes(finalFile(), 2 * 1024 * 1024);
    expect(await service.hasPartial(spec), isFalse,
        reason: 'a finished model outranks its leftover .part');
  });

  test('delete removes both the final file and any leftover .part', () async {
    await writeBytes(finalFile(), 2 * 1024 * 1024);
    final part = File('${tempDir.path}/${spec.fileName}.part');
    await writeBytes(part, 1024);

    await service.delete(spec);

    expect(finalFile().existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  group('download resumes instead of restarting from zero', () {
    late List<int> payload;
    late PeckishModelSpec testSpec;

    setUp(() {
      payload = List<int>.generate(2 * 1024 * 1024, (i) => i % 251);
      testSpec = PeckishModelSpec(
        id: 'test-model',
        displayName: 'Test',
        fileName: 'test-model.task',
        downloadUrl: 'https://example.test/model',
        sizeBytes: payload.length,
        modelType: 'qwen',
        description: 'test',
      );
    });

    ({ModelDownloadService svc, _FakeAdapter adapter}) build({
      bool ignoreRange = false,
      int? errorStatus,
    }) {
      final adapter = _FakeAdapter(payload,
          ignoreRange: ignoreRange, errorStatus: errorStatus);
      final dio = Dio()..httpClientAdapter = adapter;
      return (
        svc: ModelDownloadService(
            dio: dio, documentsDirectory: () async => tempDir),
        adapter: adapter,
      );
    }

    File partOf() => File('${tempDir.path}/${testSpec.fileName}.part');
    File modelOf() => File('${tempDir.path}/${testSpec.fileName}');

    test('a fresh download (no .part) fetches whole, no Range', () async {
      final h = build();

      await h.svc.download(testSpec).toList();

      expect(modelOf().existsSync(), isTrue);
      expect(await modelOf().length(), payload.length);
      expect(partOf().existsSync(), isFalse);
      expect(h.adapter.rangeHeaders, [null]);
    });

    test('an existing .part resumes with a Range request', () async {
      const have = 1024 * 1024;
      await partOf().writeAsBytes(payload.sublist(0, have));
      final h = build();

      await h.svc.download(testSpec).toList();

      expect(h.adapter.rangeHeaders, ['bytes=$have-']);
      expect(await modelOf().readAsBytes(), payload,
          reason: 'resumed file must equal the payload byte-for-byte');
    });

    test('an oversized .part (416) restarts cleanly from zero', () async {
      await partOf().writeAsBytes(Uint8List(payload.length + 1024 * 1024));
      final h = build();

      await h.svc.download(testSpec).toList();

      expect(await modelOf().readAsBytes(), payload);
    });

    test('a failed attempt keeps the .part for the next resume', () async {
      const have = 1024 * 1024;
      await partOf().writeAsBytes(payload.sublist(0, have));
      final h = build(errorStatus: 503);

      await expectLater(
          h.svc.download(testSpec).toList(), throwsA(isA<Object>()));

      expect(partOf().existsSync(), isTrue);
      expect(await partOf().length(), have);
    });

    test('a host that ignores Range (200) still yields a correct file',
        () async {
      await partOf().writeAsBytes(List<int>.filled(1024 * 1024, 0xFF));
      final h = build(ignoreRange: true);

      await h.svc.download(testSpec).toList();

      expect(await modelOf().readAsBytes(), payload,
          reason: 'a 200 must overwrite the .part, never append onto it');
    });
  });
}
