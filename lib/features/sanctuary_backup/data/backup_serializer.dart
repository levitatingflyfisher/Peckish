import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../settings/data/export_serializer.dart';

/// Serializes Peckish's user data to/from a JSON [Uint8List] for encrypted
/// backup via `sanctuary_backup_ui`.
///
/// Wraps the plaintext-export machinery ([PeckishExport]) rather than
/// inventing a second envelope (SANCTUARY-BRIEF §4.W2: "reuse the app's
/// existing export machinery where it exists"). Reads/writes go through the
/// [AppDatabase] handle the caller passes in — the same one the rest of the
/// app uses, never a second connection.
///
/// [UserPrefs] (shell prefs: theme) intentionally stays OUT of the backup,
/// matching `AppDatabase.eraseUserData()`'s erase boundary — a restored
/// backup should not silently flip the current device's theme out from under
/// it. Shell prefs are a device preference, not user *data*.
class PeckishBackupSerializer
    implements BackupSerializer, PreviewableBackupSerializer {
  final AppDatabase _db;

  const PeckishBackupSerializer(this._db);

  static const String _appId = 'peckish';

  @override
  Future<Uint8List> dumpAll() async {
    final export = PeckishExport(createdAt: DateTime.now());
    return Uint8List.fromList(utf8.encode(export.toPrettyJson()));
  }

  /// The dry-run parse behind preview-before-restore and export
  /// verify-by-read-back: validates exactly like [restoreAll] (wrong app,
  /// future schema, malformed shape) and reports the stamp — but never
  /// writes.
  @override
  Future<BackupManifest> describeBackup(Uint8List plaintext) async {
    PeckishExport.fromJson(jsonEncode(_unwrap(plaintext).payload));
    return BackupEnvelope.describe(plaintext);
  }

  /// Envelope validation via the shared fleet helper: rejects a blob from
  /// a different app or a future schema — defense in depth behind the AEAD
  /// context (SANCTUARY-BRIEF §2.8).
  UnwrappedBackup _unwrap(Uint8List data) => BackupEnvelope.unwrap(
        data,
        expectedAppId: _appId,
        currentSchemaVersion: PeckishExport.schemaVersion,
      );

  /// **Destructive** — wipes the domain tables ([AppDatabase.eraseUserData]'s
  /// exact set) and re-inserts inside a single transaction, so a failure
  /// partway through leaves the original data intact rather than a
  /// half-restored mix (SANCTUARY-BRIEF §2.5). Grows section-by-section with
  /// the domain schema.
  @override
  Future<void> restoreAll(Uint8List data) async {
    final payload = _unwrap(data).payload;
    PeckishExport.fromJson(jsonEncode(payload));

    await _db.transaction(() async {
      await _db.eraseUserData();
      // Domain sections are re-inserted here as they exist; the v1 shell has
      // none yet.
    });
  }
}
