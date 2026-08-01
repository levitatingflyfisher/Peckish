// Platform-selected export delivery. Native hands the JSON to the OS share
// sheet as an in-memory file (share_plus + cross_file's XFile.fromData); web
// reports that saving a file from the PWA isn't wired up yet. Both expose
// `Future<void> shareExport({content, fileName})`. IO is the default and
// `dart.library.js_interop` picks the web half — the same shape as every
// other conditional export in this app, so the analyzer resolves the real
// implementation rather than the web throw-stub.
export 'export_share_io.dart'
    if (dart.library.js_interop) 'export_share_web.dart';
