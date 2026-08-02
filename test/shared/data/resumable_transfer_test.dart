import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peckish/shared/data/resumable_transfer.dart';

/// In-memory dio transport (the model-service harness), but SLOW: the
/// payload trickles out one chunk at a time so the test can cancel the
/// subscription mid-transfer — exactly what a screen unmount does. The
/// chunk counter is the wiretap: a transfer that keeps running after the
/// listener left shows up as reads that should not exist.
class _SlowChunkAdapter implements HttpClientAdapter {
  _SlowChunkAdapter(this.payload);

  final List<int> payload;
  static const chunkSize = 1024;

  /// How many chunks the "network" has handed over.
  int chunksServed = 0;

  /// True once the whole payload went out.
  bool servedToEnd = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Stream<Uint8List> body() async* {
      for (var i = 0; i < payload.length; i += chunkSize) {
        // A real network trickles; give the listener room to cancel
        // between chunks.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        chunksServed++;
        yield Uint8List.fromList(
            payload.sublist(i, math.min(i + chunkSize, payload.length)));
      }
      servedToEnd = true;
    }

    return ResponseBody(body(), HttpStatus.ok, headers: {
      HttpHeaders.contentLengthHeader: ['${payload.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Fast variant: the whole payload in one go, for the promotion-timing test.
class _InstantAdapter implements HttpClientAdapter {
  _InstantAdapter(this.payload);

  final List<int> payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
        Uint8List.fromList(payload), HttpStatus.ok,
        headers: {
          HttpHeaders.contentLengthHeader: ['${payload.length}'],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peckish_transfer_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  File partOf() => File(p.join(tempDir.path, 'artifact.bin.part'));

  test(
      'cancelling the subscription stops the transfer, keeps the partial, '
      'and never promotes', () async {
    final payload = List<int>.generate(40 * 1024, (i) => i % 251);
    final adapter = _SlowChunkAdapter(payload);
    final dio = Dio()..httpClientAdapter = adapter;
    var promoted = false;

    final firstEvent = Completer<void>();
    final sub = resumableDownload(
      dio: dio,
      url: 'https://example.test/artifact.bin',
      partFile: partOf(),
      promote: () async => promoted = true,
    ).listen((_) {
      if (!firstEvent.isCompleted) firstEvent.complete();
    });

    await firstEvent.future;
    await sub.cancel();
    final servedAtCancel = adapter.chunksServed;

    // Ample time for a runaway detached transfer to betray itself (the
    // double-writer bug: run() kept going after the listener left).
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(adapter.chunksServed, lessThanOrEqualTo(servedAtCancel + 1),
        reason: 'the wire must go quiet once the listener leaves '
            '(at most one in-flight chunk)');
    expect(adapter.servedToEnd, isFalse,
        reason: 'the transfer must not have run to completion detached');
    expect(partOf().existsSync(), isTrue,
        reason: 'the partial is kept so Resume picks up from the same byte');
    expect(promoted, isFalse,
        reason: 'a cancelled transfer must never promote a half-file');
  });

  test('a cancel that lands during promotion lets the promotion finish',
      () async {
    final payload = List<int>.generate(4 * 1024, (i) => i % 251);
    final dio = Dio()..httpClientAdapter = _InstantAdapter(payload);

    final promoteStarted = Completer<void>();
    final promoteGate = Completer<void>();
    var promoteFinished = false;

    final sub = resumableDownload(
      dio: dio,
      url: 'https://example.test/artifact.bin',
      partFile: partOf(),
      promote: () async {
        promoteStarted.complete();
        await promoteGate.future;
        promoteFinished = true;
      },
    ).listen((_) {});

    // The transfer already completed; the listener leaving now must not
    // abort the install that is underway.
    await promoteStarted.future;
    await sub.cancel();
    promoteGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(promoteFinished, isTrue,
        reason: 'a completed transfer may finish installing quietly');
  });
}
