// Platform-selected plate-photo labeler — io default (ML Kit), web inert.
export 'plate_scanner_io.dart'
    if (dart.library.js_interop) 'plate_scanner_web.dart';
