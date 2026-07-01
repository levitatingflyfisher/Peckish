import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Native: hand [content] to the OS share sheet as an in-memory file named
/// [fileName], so the user can save it to Files/Drive or send it wherever they
/// like. The bytes never leave the device until the user picks a destination.
Future<void> shareExport({
  required String content,
  required String fileName,
}) async {
  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(content)),
    mimeType: 'application/json',
    name: fileName,
  );
  await Share.shareXFiles(
    [file],
    subject: 'Peckish export',
    fileNameOverrides: [fileName],
  );
}
