import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:peckish/features/barcode/data/barcode_db_spec.dart';

/// Downloads and manages the offline barcode slices (native builds only —
/// web uses the inert `barcode_db_download_service_web.dart` variant).
///
/// Mirrors the model downloader's proven transfer discipline (Range resume,
/// `.gz.part`, atomic rename), plus what reference data that steers meals
/// earns on top (ADR-0010): a SHA-256 check of the compressed artifact
/// before decompression. The pipeline per slice:
///
///   <fileName>.gz.part  → transfer in flight (resumable)
///   <fileName>.gz       → transfer done, awaiting sha check + gunzip
///   <fileName>.part     → gunzip in flight
///   <fileName>          → installed (the atomic rename is the ONLY path here)
class BarcodeDbDownloadService {
  BarcodeDbDownloadService({
    Dio? dio,
    Future<Directory> Function()? supportDirectory,
    List<BarcodeDbSpec>? catalog,
  })  : _dio = dio ?? Dio(),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _catalog = catalog ?? barcodeDbCatalog;

  final Dio _dio;

  /// Application SUPPORT, not documents: slices are re-downloadable
  /// reference data, not user records. Injectable so the sha/gunzip/install
  /// logic is testable without platform channels.
  final Future<Directory> Function() _supportDirectory;

  /// Injectable so tests can resolve slices that aren't shipping entries.
  final List<BarcodeDbSpec> _catalog;

  /// Every SQLite file opens with these 16 bytes — the cheap honesty check
  /// that separates a real slice from junk at the final path.
  static const _sqliteMagic = 'SQLite format 3\u0000';

  Future<Directory> _dbDir() async {
    final dir = await _supportDirectory();
    final sub = Directory(p.join(dir.path, 'barcode_dbs'));
    if (!sub.existsSync()) await sub.create(recursive: true);
    return sub;
  }

  Future<File> _installed(BarcodeDbSpec spec) async =>
      File(p.join((await _dbDir()).path, spec.fileName));
  Future<File> _gz(BarcodeDbSpec spec) async =>
      File(p.join((await _dbDir()).path, '${spec.fileName}.gz'));
  Future<File> _gzPart(BarcodeDbSpec spec) async =>
      File(p.join((await _dbDir()).path, '${spec.fileName}.gz.part'));
  Future<File> _dbPart(BarcodeDbSpec spec) async =>
      File(p.join((await _dbDir()).path, '${spec.fileName}.part'));

  /// A file at the final path IS a finished install (the atomic rename is
  /// the only way it gets there); only non-sqlite junk is rejected —
  /// removed so it can never shadow a real download.
  Future<bool> isInstalled(BarcodeDbSpec spec) async {
    final file = await _installed(spec);
    if (!file.existsSync()) return false;
    final head = await file
        .openRead(0, _sqliteMagic.length)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    if (String.fromCharCodes(head) != _sqliteMagic) {
      await file.delete();
      return false;
    }
    return true;
  }

  /// A half-finished transfer is waiting on disk (and the slice isn't
  /// installed yet): the UI shows Resume instead of Download.
  Future<bool> hasPartial(BarcodeDbSpec spec) async {
    if (await isInstalled(spec)) return false;
    final part = await _gzPart(spec);
    return part.existsSync();
  }

  /// The absolute path of an installed slice, or null — the lookup chain's
  /// single question. Resolves [id] via the catalog so callers never carry
  /// specs around.
  Future<String?> installedDbPath(String id) async {
    for (final spec in _catalog) {
      if (spec.id != id) continue;
      if (!await isInstalled(spec)) return null;
      return (await _installed(spec)).path;
    }
    return null;
  }

  /// Downloads [spec], yielding `(receivedBytes, totalBytes)` tuples for
  /// the compressed transfer (total is `-1` when the server omits
  /// Content-Length). After the last tuple the stream stays open briefly
  /// for the sha check + gunzip, then closes on success.
  ///
  /// Resumable exactly like the model downloader: an interrupted attempt's
  /// `.gz.part` continues with an HTTP Range request; the partial is KEPT
  /// on error; a 416 (partial larger than the resource) discards and
  /// restarts; a host that ignores Range (200 instead of 206) also
  /// discards — appending onto stale bytes would corrupt the file.
  ///
  /// Integrity: the finished .gz must hash to [BarcodeDbSpec.sha256Gz]
  /// before it is decompressed. A mismatch deletes the .gz and throws
  /// [BarcodeDbIntegrityException]; a 'PENDING' hash is a programming
  /// error and fails closed before any network.
  Stream<(int, int)> download(BarcodeDbSpec spec) async* {
    if (spec.sha256Gz == 'PENDING') {
      throw StateError(
          'Catalog entry "${spec.id}" has no measured sha256Gz yet — '
          'a slice without a hash is never downloadable (ADR-0010).');
    }
    final gz = await _gz(spec);
    final gzPart = await _gzPart(spec);
    final controller = StreamController<(int, int)>();

    Future<void> run() async {
      final resumeFrom = gzPart.existsSync() ? await gzPart.length() : 0;
      final reqHeaders = <String, dynamic>{
        if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
      };

      Response<dynamic> response;
      var restarted = false;
      try {
        response = await _dio.download(
          spec.downloadUrl,
          gzPart.path,
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
          if (gzPart.existsSync()) await gzPart.delete();
          response = await _dio.download(
            spec.downloadUrl,
            gzPart.path,
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
        if (gzPart.existsSync()) await gzPart.delete();
        await _dio.download(
          spec.downloadUrl,
          gzPart.path,
          onReceiveProgress: (received, total) =>
              controller.add((received, total)),
          deleteOnError: false,
        );
      }

      // Transfer done: promote to .gz and verify before touching it.
      if (gz.existsSync()) await gz.delete();
      await gzPart.rename(gz.path);

      final digest = await sha256.bind(gz.openRead()).first;
      if (digest.toString() != spec.sha256Gz.toLowerCase()) {
        await gz.delete();
        throw BarcodeDbIntegrityException(
            'Downloaded "${spec.id}" did not match its published checksum. '
            'The file was removed — trying again is safe.');
      }

      // Verified: gunzip streaming to .part, then the atomic promotion —
      // only now may [isInstalled] say true.
      final dbPart = await _dbPart(spec);
      await gz.openRead().transform(gzip.decoder).pipe(dbPart.openWrite());
      final installed = await _installed(spec);
      if (installed.existsSync()) await installed.delete();
      await dbPart.rename(installed.path);
      await gz.delete();
    }

    unawaited(run().then((_) => controller.close(), onError: (Object e) {
      controller.addError(e);
      controller.close();
    }));

    yield* controller.stream;
  }

  /// Deletes the installed slice and every intermediate.
  Future<void> delete(BarcodeDbSpec spec) async {
    for (final file in [
      await _installed(spec),
      await _gz(spec),
      await _gzPart(spec),
      await _dbPart(spec),
    ]) {
      if (file.existsSync()) await file.delete();
    }
  }
}
