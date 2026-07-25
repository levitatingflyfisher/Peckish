import 'package:peckish/features/settings/domain/user_prefs.dart';

abstract interface class SettingsRepository {
  Future<UserPrefs> getUserPrefs();
  Stream<UserPrefs> watchUserPrefs();
  Future<void> setDarkMode(bool dark);
}
