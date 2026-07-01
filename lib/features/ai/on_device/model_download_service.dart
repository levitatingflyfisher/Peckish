// Platform-selected model downloader (the Reckon pattern). The NATIVE file
// is the default branch — its API (`modelFile` → dart:io File, injectable
// dio/directory ctor) isn't expressible platform-neutrally, and the
// analyzer + native builds resolve the default. `dart.library.js_interop`
// exists only on web, so the web build gets the inert variant and never
// compiles dart:io.
export 'model_download_service_io.dart'
    if (dart.library.js_interop) 'model_download_service_web.dart';
