// lib/core/providers/core_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:peckish/core/auth/auth_repository.dart';
import 'package:peckish/core/auth/ghost_auth_repository.dart';
import 'package:peckish/core/storage/app_database.dart' hide UserPrefs;
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/data/food_usage_repository.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
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
UsdaFoodRepository usdaFoodRepository(Ref ref) =>
    UsdaFoodRepository(ref.watch(appDatabaseProvider));

@riverpod
CustomFoodRepository customFoodRepository(Ref ref) =>
    CustomFoodRepository(ref.watch(appDatabaseProvider));

@riverpod
FoodUsageRepository foodUsageRepository(Ref ref) =>
    FoodUsageRepository(ref.watch(appDatabaseProvider));

@riverpod
DiaryRepository diaryRepository(Ref ref) =>
    DiaryRepository(ref.watch(appDatabaseProvider));

@riverpod
SavedMealRepository savedMealRepository(Ref ref) =>
    SavedMealRepository(ref.watch(appDatabaseProvider));

@riverpod
TargetsRepository targetsRepository(Ref ref) =>
    TargetsRepository(ref.watch(appDatabaseProvider));

@riverpod
RecipeRepository recipeRepository(Ref ref) =>
    RecipeRepository(ref.watch(appDatabaseProvider));

@riverpod
PlanRepository planRepository(Ref ref) =>
    PlanRepository(ref.watch(appDatabaseProvider));

@riverpod
GroceryRepository groceryRepository(Ref ref) =>
    GroceryRepository(ref.watch(appDatabaseProvider));

/// Boot-time spine import: loads the bundled USDA asset and imports it if the
/// shipped version is newer than what's in the database. Idempotent and
/// version-stamped, so this is cheap on every boot after the first. Search
/// surfaces watch this so they can show a friendly "setting the table"
/// state during the very first import.
@Riverpod(keepAlive: true)
Future<void> spineReady(Ref ref) async {
  final json = await rootBundle.loadString('assets/food/usda_foods.json');
  await ref.watch(usdaFoodRepositoryProvider).importSpine(json);
}

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
