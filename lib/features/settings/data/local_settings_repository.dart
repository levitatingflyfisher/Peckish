import 'package:peckish/core/storage/app_database.dart' hide UserPrefs;
import 'package:peckish/features/settings/domain/settings_repository.dart';
import 'package:peckish/features/settings/domain/user_prefs.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._db);
  final AppDatabase _db;

  static const _kDarkMode = 'theme';

  Future<void> _set(String key, String value) => _db
      .into(_db.userPrefs)
      .insertOnConflictUpdate(UserPrefsCompanion.insert(key: key, value: value));

  @override
  Future<UserPrefs> getUserPrefs() async {
    final rows = await _db.select(_db.userPrefs).get();
    final map = {for (final r in rows) r.key: r.value};
    return _fromMap(map);
  }

  @override
  Stream<UserPrefs> watchUserPrefs() =>
      _db.select(_db.userPrefs).watch().map((rows) {
        final map = {for (final r in rows) r.key: r.value};
        return _fromMap(map);
      });

  @override
  Future<void> setDarkMode(bool dark) =>
      _set(_kDarkMode, dark ? 'dark' : 'light');

  UserPrefs _fromMap(Map<String, String> map) =>
      UserPrefs(isDarkMode: map[_kDarkMode] == 'dark');
}
