// Platform-selected barcode-slice downloader (the model-downloader
// pattern). The NATIVE file is the default branch — its API (dart:io File
// storage, injectable dio/directory ctor) isn't expressible
// platform-neutrally, and the analyzer + native builds resolve the
// default. `dart.library.js_interop` exists only on web, so the web build
// gets the inert variant and never compiles dart:io.
export 'barcode_db_download_service_io.dart'
    if (dart.library.js_interop) 'barcode_db_download_service_web.dart';
