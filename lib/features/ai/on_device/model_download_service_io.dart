import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:peckish/features/ai/on_device/model_spec.dart';

/// Downloads and manages the on-device model files (native builds only —
/// web uses the inert `model_download_service_web.dart` variant).
///
/// Ported from Reckon's proven service, minus the HuggingFace-token
/// machinery: Peckish's catalog is ungated by law (see model_spec_test),
/// so a gated spec is a programming error, not a configuration to support.
class ModelDownloadService {
  ModelDownloadService({
    Dio? dio,
    Future<Directory> Function()? documentsDirectory,
  })  : _dio = dio ?? Dio(),
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final Dio _dio;

  /// Injectable so the completion/validation logic is testable without
  /// platform channels.
  final Future<Directory> Function() _documentsDirectory;

  /// A final model file under this size is junk (0-byte / garbage) and is
  /// removed. NOT a completeness check against the approximate size —
  /// completeness is guaranteed by download-to-`.part`-then-rename (the
  /// Reckon scar: size-guessing deleted real, correctly-sized models).
  static const _minValidBytes = 1024 * 1024; // 1 MB

  Future<File> modelFile(PeckishModelSpec spec) async {
    final dir = await _documentsDirectory();
    return File(p.join(dir.path, spec.fileName));
  }

  Future<File> _partFile(PeckishModelSpec spec) async {
    final dir = await _documentsDirectory();
    return File(p.join(dir.path, '${spec.fileName}.part'));
  }

  /// A file at the final path IS a finished transfer (the atomic rename is
  /// the only way it gets there); only empty/garbage files are rejected.
  Future<bool> isDownloaded(PeckishModelSpec spec) async {
    final file = await modelFile(spec);
    if (!file.existsSync()) return false;
    if (await file.length() < _minValidBytes) {
      await file.delete();
      return false;
    }
    return true;
  }

  /// A half-finished transfer is waiting on disk (and the final file
  /// isn't there yet): the UI shows Resume instead of Download. Leaving
  /// the app pauses a transfer — the .part is the progress that survives.
  Future<bool> hasPartial(PeckishModelSpec spec) async {
    if (await isDownloaded(spec)) return false;
    final part = await _partFile(spec);
    return part.existsSync();
  }

  /// Downloads [spec], yielding `(receivedBytes, totalBytes)` tuples
  /// (total is `-1` when the server omits Content-Length).
  ///
  /// Resumable: an interrupted attempt's `.part` is continued with an HTTP
  /// Range request instead of restarting from zero (what kept happening
  /// when a phone slept mid-download). The partial is deliberately KEPT on
  /// error so the next attempt picks up where this one stopped. A 416
  /// (partial larger than the resource) discards and restarts; a host that
  /// ignores Range (200 instead of 206) also discards — appending onto
  /// stale bytes would corrupt the file.
  Stream<(int, int)> download(PeckishModelSpec spec) async* {
    if (spec.requiresToken) {
      throw StateError(
          'Gated models are not part of this catalog (model_spec_test).');
    }
    final file = await modelFile(spec);
    final part = await _partFile(spec);
    final controller = StreamController<(int, int)>();

    Future<void> run() async {
      final resumeFrom = part.existsSync() ? await part.length() : 0;
      final reqHeaders = <String, dynamic>{
        if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
      };

      Response<dynamic> response;
      var restarted = false;
      try {
        response = await _dio.download(
          spec.downloadUrl,
          part.path,
          options: Options(headers: reqHeaders),
          onReceiveProgress: (received, total) {
            // dio reports progress relative to THIS request; offset it so
            // the UI tracks the whole file when resuming.
            controller.add((
              resumeFrom + received,
              total < 0 ? -1 : resumeFrom + total,
            ));
          },
          // Keep the partial on error so a later attempt can resume.
          deleteOnError: false,
          fileAccessMode:
              resumeFrom > 0 ? FileAccessMode.append : FileAccessMode.write,
        );
      } on DioException catch (err) {
        if (resumeFrom > 0 &&
            err.response?.statusCode ==
                HttpStatus.requestedRangeNotSatisfiable) {
          if (part.existsSync()) await part.delete();
          response = await _dio.download(
            spec.downloadUrl,
            part.path,
            onReceiveProgress: (received, total) =>
                controller.add((received, total)),
            deleteOnError: false,
          );
          restarted = true;
        } else {
          rethrow;
        }
      }

      if (!restarted &&
          resumeFrom > 0 &&
          response.statusCode == HttpStatus.ok) {
        if (part.existsSync()) await part.delete();
        await _dio.download(
          spec.downloadUrl,
          part.path,
          onReceiveProgress: (received, total) =>
              controller.add((received, total)),
          deleteOnError: false,
        );
      }

      // Atomic promotion — only now may [isDownloaded] say true.
      if (file.existsSync()) await file.delete();
      await part.rename(file.path);
    }

    unawaited(run().then((_) => controller.close(), onError: (Object e) {
      controller.addError(e);
      controller.close();
    }));

    yield* controller.stream;
  }

  /// Deletes the local model file (and any leftover `.part`).
  Future<void> delete(PeckishModelSpec spec) async {
    final file = await modelFile(spec);
    if (file.existsSync()) await file.delete();
    final part = await _partFile(spec);
    if (part.existsSync()) await part.delete();
  }
}
