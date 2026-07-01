// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart' as sanctuary;
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/router/app_router.dart';
import 'package:peckish/features/sanctuary_backup/backup_config.dart';
import 'package:peckish/features/sanctuary_backup/data/backup_serializer.dart';
import 'package:peckish/shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Encrypted-backup wiring (sanctuary_backup_ui). Peckish is a new app
        // (not a legacy Lullaby-style carry-over), so — unlike Lullaby — it
        // sets an explicit appDomain: this app's key material is isolated
        // from any other OpenHearth app sharing the same household seed
        // phrase (SANCTUARY-BRIEF §2.1). Aliased `as sanctuary` so its
        // AuthState/AuthTier can never collide with Peckish's own unrelated
        // core/auth/auth_state.dart stub types of the same name.
        sanctuary.sanctuaryAppDomainProvider.overrideWithValue('peckish'),
        sanctuaryBackupConfigProvider.overrideWithValue(peckishBackupConfig),
        backupSerializerProvider.overrideWith(
          (ref) => PeckishBackupSerializer(ref.watch(appDatabaseProvider)),
        ),
      ],
      child: const PeckishApp(),
    ),
  );
}

class PeckishApp extends ConsumerStatefulWidget {
  const PeckishApp({super.key});

  @override
  ConsumerState<PeckishApp> createState() => _PeckishAppState();
}

class _PeckishAppState extends ConsumerState<PeckishApp> {
  @override
  void initState() {
    super.initState();
    // Silent freshness snapshot (BACKUP_RETENTION_SPEC §3): if the newest
    // vault snapshot is >7 days old and a backup key exists, take one.
    // Post-frame + fire-and-forget — never blocks boot, never surfaces
    // errors (the Sundial/Lullaby startup pattern).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupControllerProvider.notifier).runStartupMaintenance();
      // Kick the USDA spine import (idempotent, version-stamped). Fire-and-
      // forget: first boot imports ~13.6k foods in the background; every
      // later boot is a single version-stamp read.
      ref.read(spineReadyProvider.future).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Peckish',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // On wide screens keep the single-column app centered at a comfortable
      // reading width rather than stretching edge-to-edge (phones pass through).
      builder: (context, child) {
        final inner = child ?? const SizedBox.shrink();
        if (MediaQuery.of(context).size.width <= 760) return inner;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(child: SizedBox(width: 760, child: inner)),
        );
      },
    );
  }
}
