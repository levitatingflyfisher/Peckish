import 'dart:io';

import 'package:dio/dio.dart';
import 'package:domovoi/domovoi.dart' as domovoi;
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
  /// The `.part` resume / 416-restart / 200-ignores-Range discipline
  /// belongs to domovoi's transfer engine — see its docs for the story.
  /// The stream starts on subscribe and the listener leaving cancels it.
  Stream<(int, int)> download(PeckishModelSpec spec) async* {
    if (spec.requiresToken) {
      throw StateError(
          'Gated models are not part of this catalog (model_spec_test).');
    }
    final file = await modelFile(spec);
    final part = await _partFile(spec);
    yield* domovoi.resumableDownloadStream(
      dio: _dio,
      url: spec.downloadUrl,
      partFile: part,
      promote: () async {
        // Atomic promotion — only now may [isDownloaded] say true.
        if (file.existsSync()) await file.delete();
        await part.rename(file.path);
      },
    );
  }

  /// Deletes the local model file (and any leftover `.part`).
  Future<void> delete(PeckishModelSpec spec) async {
    final file = await modelFile(spec);
    if (file.existsSync()) await file.delete();
    final part = await _partFile(spec);
    if (part.existsSync()) await part.delete();
  }
}
