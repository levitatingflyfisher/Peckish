import 'package:flutter/material.dart';

import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The WeatherGlass pattern: one screen mapping every network touch the
/// app can make, so "it worked with data off" reads as the design it is,
/// not a surprise. Anything not on this list stays on the phone — and the
/// docs' privacy reference mirrors this screen line for line.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(
              top: AppSpacing.lg, bottom: AppSpacing.sm),
          child: Text(title, style: theme.textTheme.titleMedium),
        );
    Widget row(IconData icon, String title, String body,
            {Color color = AppColors.sage}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(body, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('What leaves your device')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Peckish is built to work with the internet OFF. Everything '
            'below the first section only happens when you take the '
            'action it names — and sends only what it names.',
            style: theme.textTheme.bodyMedium,
          ),
          section('Every day — nothing leaves'),
          row(Icons.wifi_off_outlined, 'Logging, planning, groceries, history',
              'The 13,652-food database is bundled inside the app. Search, '
              'portions, targets, suggestions, charts: all on-phone, '
              'nothing leaves, data off is a normal day.'),
          row(Icons.photo_camera_outlined, 'Snap your plate',
              'The photo never leaves. Labels are computed on the phone by '
              'the system classifier — that one piece rides Google Play '
              'services, so on a de-Googled phone this button bows out '
              'and everything else carries on.'),
          row(Icons.psychology_outlined, '"On this phone" AI',
              'Guesses run inside the downloaded model — nothing leaves, '
              'not even the words. The one network touch is the download '
              'itself, below.'),
          section('Only when you act'),
          row(Icons.qr_code_scanner, 'Barcode scan',
              'With the offline database, scans are answered on the phone. '
              'A miss only goes online when you tap Ask openfoodfacts.org — '
              'the 13 digits, nothing else.',
              color: AppColors.butter),
          row(Icons.qr_code_2_outlined, 'Offline barcode database',
              'Tapping Download fetches a database file from github.com, '
              'once. After that, scans stay on the phone. Delete it any '
              'time.',
              color: AppColors.butter),
          row(Icons.download_outlined, 'Model download',
              'Tapping Download fetches the model file from huggingface.co '
              '(the trusted litert-community org). Delete it any time.',
              color: AppColors.butter),
          row(Icons.link_outlined, 'Recipe import',
              'The one recipe URL you paste is fetched, parsed, and '
              'discarded.',
              color: AppColors.butter),
          row(Icons.auto_awesome_outlined, 'Claude / local server AI',
              'If you configured one, the words you type in the guess box '
              'go to that service and nowhere else. Off by default.',
              color: AppColors.butter),
          row(Icons.fireplace_outlined, 'AI guess via your home stove',
              'The guess-box words travel sealed under your household '
              'phrase — encrypted to your own machine, only when you ask, '
              'and nowhere else.',
              color: AppColors.butter),
          row(Icons.sync_outlined, 'Household sync',
              'Encrypted bundles move between your own devices on your own '
              'Wi-Fi. Diaries and targets never sync at all.',
              color: AppColors.butter),
          section('Never'),
          row(Icons.block_outlined, 'No accounts, no analytics, no fonts CDN',
              'No sign-in exists, nothing is tracked, and the fonts ship '
              'inside the app.',
              color: AppColors.clay),
        ],
      ),
    );
  }
}
