// lib/core/providers/core_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:peckish/core/auth/auth_repository.dart';
import 'package:peckish/core/auth/ghost_auth_repository.dart';
import 'package:peckish/core/storage/app_database.dart' hide UserPrefs;
import 'package:peckish/features/settings/data/local_settings_repository.dart';
import 'package:peckish/features/settings/domain/settings_repository.dart';
import 'package:peckish/features/settings/domain/user_prefs.dart';

part 'core_providers.g.dart';

// Seeded from main() before ProviderScope.
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

@riverpod
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalSettingsRepository(db);
}

@riverpod
AuthRepository authRepository(Ref ref) => GhostAuthRepository();

@riverpod
Stream<UserPrefs> userPrefs(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watchUserPrefs();

@riverpod
ThemeMode themeMode(Ref ref) {
  final prefs = ref.watch(userPrefsProvider);
  return prefs.when(
    data: (p) => p.isDarkMode ? ThemeMode.dark : ThemeMode.light,
    loading: () => ThemeMode.system,
    error: (_, __) => ThemeMode.system,
  );
}
