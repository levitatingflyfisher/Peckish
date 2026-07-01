/// Web: saving an export file to disk from the PWA isn't wired up yet, so this
/// fails cleanly with a message the Settings screen shows in a snackbar rather
/// than crashing. Nothing was gathered off the device — the data is still only
/// here; use the Android app to write the file out.
Future<void> shareExport({
  required String content,
  required String fileName,
}) async {
  throw UnsupportedError(
    "Saving an export file isn't available in the web version of Peckish yet "
    '— use the Android app to export your data.',
  );
}
