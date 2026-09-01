import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/settings/data/local_settings_repository.dart';

// Fleet theme ruling: light, dark, or follow the phone, defaulting to follow
// the phone (lens audit unix-02: a phone set to dark opened Peckish in cream
// until the switch was found). The old switch stored 'theme' = dark/light.
// A stored dark stays dark; a stored light becomes follow-the-phone, since
// light was the default and most 'light' rows mean "never chosen"
// (operator ruling; one tap puts a deliberate light back).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> legacy(String value) => db.into(db.userPrefs).insert(
      UserPrefsCompanion.insert(key: 'theme', value: value));

  Future<OhThemeModePreference> read() async =>
      (await LocalSettingsRepository(db).getUserPrefs()).themeMode;

  test('nothing stored follows the phone', () async {
    expect(await read(), OhThemeModePreference.system);
  });

  test('a stored dark from the old switch stays dark', () async {
    await legacy('dark');
    expect(await read(), OhThemeModePreference.dark);
  });

  test('a stored light from the old switch follows the phone', () async {
    await legacy('light');
    expect(await read(), OhThemeModePreference.system);
  });

  test('a choice survives a restart, and wins over the old key', () async {
    await legacy('dark');
    await LocalSettingsRepository(db)
        .setThemeMode(OhThemeModePreference.light);
    // A fresh repository over the same database: a restart.
    expect(await read(), OhThemeModePreference.light);
  });

  test('Erase all data keeps the theme choice, as its copy promises',
      () async {
    await LocalSettingsRepository(db).setThemeMode(OhThemeModePreference.dark);
    await db.eraseUserData();
    expect(await read(), OhThemeModePreference.dark);
  });

  test('themeModeProvider hands MaterialApp the preference', () async {
    await LocalSettingsRepository(db).setThemeMode(OhThemeModePreference.dark);
    final c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    c.listen(themeModeProvider, (_, __) {});
    await c.read(userPrefsProvider.future);
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });
}
