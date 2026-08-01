// Platform-selected offline barcode slice reader (the model-downloader
// pattern). The NATIVE file is the default branch — its sqlite3 file API
// isn't expressible platform-neutrally, and the analyzer + native builds
// resolve the default. `dart.library.js_interop` exists only on web, so the
// web build gets the inert variant and never compiles package:sqlite3's ffi.
export 'local_barcode_db_io.dart'
    if (dart.library.js_interop) 'local_barcode_db_web.dart';
