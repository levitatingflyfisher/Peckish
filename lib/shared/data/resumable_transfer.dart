import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// The one resumable-transfer engine behind every big download in the app
/// (model files, barcode slices — native builds only; web uses each
/// service's inert `_web` variant and never compiles this file).
///
/// Transfers [url] into [partFile], yielding `(receivedBytes, totalBytes)`
/// tuples (total is `-1` when the server omits Content-Length).
///
/// Resumable: an interrupted attempt's partial is continued with an HTTP
/// Range request instead of restarting from zero (what kept happening
/// when a phone slept mid-download). The partial is deliberately KEPT on
/// error so the next attempt picks up where this one stopped. A 416
/// (partial larger than the resource) discards and restarts; a host that
/// ignores Range (200 instead of 206) also discards — appending onto
/// stale bytes would corrupt the file.
///
/// After the last byte, [promote] runs the caller's own post-transfer
/// step (the model file's atomic rename; the barcode slice's sha check +
/// gunzip + rename) before the stream closes — so a listener that hears
/// `done` knows the artifact is fully installed. An error anywhere
/// (transfer or promotion) reaches the listener as a stream error.
///
/// The listener leaving IS the pause button: cancelling the subscription
/// (a screen unmount, a mid-download navigation) cancels the transfer
/// itself. Without that, the detached transfer kept appending while the
/// next visit's Resume opened a SECOND writer on the same partial — two
/// appenders, one corrupt file. A cancelled transfer ends quietly: the
/// partial stays for Resume, [promote] never runs. If the transfer had
/// already completed, the promotion underway is allowed to finish — the
/// artifact is whole, installing it loses nothing.
Stream<(int, int)> resumableDownload({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
}) {
  final cancelToken = CancelToken();
  // The listener's unsubscribe reaches the wire through this token; on a
  // stream that already finished, cancel() is a harmless no-op.
  final controller =
      StreamController<(int, int)>(onCancel: cancelToken.cancel);

  Future<void> run() async {
    final resumeFrom = partFile.existsSync() ? await partFile.length() : 0;
    final reqHeaders = <String, dynamic>{
      if (resumeFrom > 0) 'Range': 'bytes=$resumeFrom-',
    };

    Response<dynamic> response;
    var restarted = false;
    try {
      response = await dio.download(
        url,
        partFile.path,
        options: Options(headers: reqHeaders),
        cancelToken: cancelToken,
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
        if (partFile.existsSync()) await partFile.delete();
        response = await dio.download(
          url,
          partFile.path,
          cancelToken: cancelToken,
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
      if (partFile.existsSync()) await partFile.delete();
      await dio.download(
        url,
        partFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) =>
            controller.add((received, total)),
        deleteOnError: false,
      );
    }

    await promote();
  }

  unawaited(run().then((_) => controller.close(), onError: (Object e) {
    // The listener's own cancel ends the run quietly: nobody is left to
    // hear an error, and the kept partial is the whole story.
    if (e is DioException && e.type == DioExceptionType.cancel) {
      controller.close();
      return;
    }
    controller.addError(e);
    controller.close();
  }));

  return controller.stream;
}
