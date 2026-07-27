import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/presentation/ai_settings_dialog.dart';
import 'package:peckish/features/settings/data/export_serializer.dart';
import 'package:peckish/features/settings/data/export_share.dart';
import 'package:peckish/features/settings/data/plain_export.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

/// Settings: appearance, encrypted backup, plaintext export, erase, About.
/// Calm and reversible throughout — every destructive action confirms first
/// and says exactly what it will do.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Dark theme'),
            value: prefs.value?.isDarkMode ?? false,
            onChanged: (dark) =>
                ref.read(settingsRepositoryProvider).setDarkMode(dark),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Your data', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // Encrypted .ohbk backup + restore (sanctuary_backup_ui).
          const BackupSettingsSection(),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Export data (plain JSON)'),
            subtitle: const Text('A readable copy you own — keep it anywhere.'),
            onTap: () async {
              // Gathered through the same snapshot the encrypted backup
              // uses (v0.1 exported an empty shell here).
              final json =
                  await buildPlainExport(ref.read(appDatabaseProvider));
              await shareExport(
                fileName: exportFileName(DateTime.now()),
                content: json,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Erase all data'),
            subtitle: const Text('Deletes everything on this device.'),
            onTap: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Erase all data?',
                message: 'This deletes all Peckish data on this device. '
                    'Your theme preference is kept. This cannot be undone.',
                confirmLabel: 'Erase',
              );
              if (!confirmed) return;
              await eraseAllData(ref);
              if (context.mounted) context.go('/');
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Household', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('Household sync'),
            subtitle: const Text(
                'One plan, one list, every device — encrypted, on your own '
                'Wi-Fi. Diaries stay personal.'),
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Intelligence', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI guesstimate'),
            subtitle: const Text(
                'Off by default. Your own key or your own local server.'),
            onTap: () => showAiSettingsDialog(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Peckish'),
            onTap: () => context.go('/about'),
          ),
        ],
      ),
    );
  }
}
