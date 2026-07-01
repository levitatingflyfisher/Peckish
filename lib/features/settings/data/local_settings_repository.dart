import 'package:peckish/core/storage/app_database.dart' hide UserPrefs;
import 'package:peckish/features/settings/domain/settings_repository.dart';
import 'package:peckish/features/settings/domain/user_prefs.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._db);
  final AppDatabase _db;

  static const _kDarkMode = 'theme';
  static const _kSuggest = 'suggest.enabled';
  static const _kSuggestDismissed = 'suggest.dismissed';

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
      // distinct() is load-bearing: this table also holds the sync clock's
      // HLC row, which advances on every synced write. Without value-level
      // de-duplication those writes masquerade as pref changes and rebuild
      // every prefs watcher mid-write (found as a wedged quick-add save).
      _db.select(_db.userPrefs).watch().map((rows) {
        final map = {for (final r in rows) r.key: r.value};
        return _fromMap(map);
      }).distinct();

  @override
  Future<void> setDarkMode(bool dark) =>
      _set(_kDarkMode, dark ? 'dark' : 'light');

  @override
  Future<void> setSuggestionsEnabled(bool enabled) =>
      _set(_kSuggest, enabled ? 'on' : 'off');

  @override
  Future<void> setSuggestionsDismissedDay(String day) =>
      _set(_kSuggestDismissed, day);

  UserPrefs _fromMap(Map<String, String> map) => UserPrefs(
        isDarkMode: map[_kDarkMode] == 'dark',
        // Absent = on: the card is part of the product until switched off.
        suggestionsEnabled: map[_kSuggest] != 'off',
        suggestionsDismissedDay: map[_kSuggestDismissed],
      );
}
