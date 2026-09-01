import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/features/settings/domain/user_prefs.dart';

abstract interface class SettingsRepository {
  Future<UserPrefs> getUserPrefs();
  Stream<UserPrefs> watchUserPrefs();
  Future<void> setThemeMode(OhThemeModePreference mode);
  Future<void> setSuggestionsEnabled(bool enabled);
  Future<void> setSuggestionsDismissedDay(String day);
}
