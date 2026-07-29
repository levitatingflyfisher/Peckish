import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';

/// Which side of the scan screen the user last chose.
enum ScanMode { camera, type }

/// Remembers the Scan/Type choice across sessions in the UserPrefs KV table
/// (same pattern as LocalSettingsRepository). Camera-less platforms never
/// ask; this exists so a phone that always types stops seeing the camera.
class ScanModeStore {
  ScanModeStore(this._db);
  final AppDatabase _db;

  static const _key = 'scan.mode';

  /// Null when the user has never chosen — callers pick the platform default.
  Future<ScanMode?> load() async {
    final row = await (_db.select(_db.userPrefs)
          ..where((t) => t.key.equals(_key)))
        .getSingleOrNull();
    return switch (row?.value) {
      'camera' => ScanMode.camera,
      'type' => ScanMode.type,
      _ => null,
    };
  }

  Future<void> save(ScanMode mode) =>
      _db.into(_db.userPrefs).insertOnConflictUpdate(UserPrefsCompanion.insert(
          key: _key, value: mode == ScanMode.camera ? 'camera' : 'type'));
}

final scanModeStoreProvider = Provider<ScanModeStore>(
    (ref) => ScanModeStore(ref.watch(appDatabaseProvider)));
