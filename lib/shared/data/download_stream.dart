import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:domovoi/domovoi.dart' as domovoi;

/// The stream façade over domovoi's `resumableDownload` — the ONE transfer
/// engine behind every big download (model files, barcode slices; native
/// builds only, web services keep their inert variants). The engine's laws
/// (Range resume, 416 restart, 200-ignores-Range restart, promote-once,
/// completion = the caller's atomic rename) live in and are proven by
/// domovoi; what lives here is the dialect Peckish's services and download
/// cards already speak:
///
/// - progress arrives as `(receivedBytes, totalBytes)` tuples, `-1` when
///   the server omits Content-Length (domovoi says `null`);
/// - the listener leaving IS the pause button: cancelling the subscription
///   cancels the transfer itself (the double-writer scar — a detached
///   transfer appending while the next visit's Resume opened a second
///   writer — must never reopen). The partial stays for Resume and
///   [promote] never runs; a promotion already underway is allowed to
///   finish.
Stream<(int, int)> downloadStream({
  required Dio dio,
  required String url,
  required File partFile,
  required Future<void> Function() promote,
}) {
  final cancelToken = CancelToken();
  // The listener's unsubscribe reaches the wire through this token; on a
  // transfer that already finished, cancel() is a harmless no-op.
  final controller = StreamController<(int, int)>(onCancel: cancelToken.cancel);

  unawaited(domovoi
      .resumableDownload(
    dio: dio,
    url: url,
    partFile: partFile,
    promote: promote,
    cancelToken: cancelToken,
    onProgress: (received, total) => controller.add((received, total ?? -1)),
  )
      .then((_) => controller.close(), onError: (Object e) {
    controller.addError(e);
    controller.close();
  }));

  return controller.stream;
}
