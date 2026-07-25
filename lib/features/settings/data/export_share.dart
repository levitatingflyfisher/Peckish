// Platform-selected export delivery. Native hands the JSON to the OS share
// sheet as an in-memory file (share_plus + cross_file's XFile.fromData); web
// reports that saving a file from the PWA isn't wired up yet. Both expose
// `Future<void> shareExport({content, fileName})`. `dart.library.io` picks the
// right one — the same idiom the rest of the fleet uses.
export 'export_share_web.dart' if (dart.library.io) 'export_share_io.dart';
