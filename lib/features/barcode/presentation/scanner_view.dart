/// Splits the camera scanner by capability: FFI platforms get zxing-cpp,
/// the web build gets the stub (manual entry is the universal path).
library;

export 'scanner_view_stub.dart'
    if (dart.library.ffi) 'scanner_view_zxing.dart';
