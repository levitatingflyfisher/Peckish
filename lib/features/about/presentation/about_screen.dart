import 'package:flutter/material.dart';

import 'package:peckish/core/app_info.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// About: what Peckish is, why it's local-first and free, the version, a link
/// to the open-source licenses, and the data-attribution statement.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(AppInfo.appName, style: text.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppInfo.tagline,
            style: text.titleMedium?.copyWith(color: AppColors.jam),
          ),
          const SizedBox(height: AppSpacing.lg),

          const _Section(
            title: 'What Peckish is',
            body: 'Peckish is the family food app: a recipe box, a weekly '
                'dinner plan, the grocery list that writes itself from the '
                'plan, and a quiet one-tap food diary for anyone in the house '
                'who wants their own numbers. Nutrition here describes meals — '
                'what the week looks like — so the household can feed itself '
                'well without ceremony.',
          ),
          const _Section(
            title: 'Free and open',
            body: 'Peckish is free and open-source software. There are no '
                'accounts, no ads, no tracking, and no subscriptions — the app '
                'is not built to monetize you.',
          ),
          const _Section(
            title: 'Your data stays here',
            body: 'Everything lives on this device. The food database is '
                'bundled, so lookups work offline; the network is touched only '
                'when you ask it to be — fetching a recipe page you pasted, or '
                'looking up a barcode. Export and encrypted backup give you '
                'copies you own; nothing is ever uploaded.',
          ),
          const _Section(
            title: 'Food data',
            body: 'Generic-food nutrition comes from USDA FoodData Central '
                '(public domain, bundled with the app). Peckish is not '
                'medical or dietary advice — for anything clinical, talk to a '
                'professional.',
          ),

          const SizedBox(height: AppSpacing.sm),
          Text('Version ${AppInfo.appVersion}',
              style: text.bodyMedium?.copyWith(color: AppColors.stone)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Open-source licenses'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppInfo.appName,
              applicationVersion: AppInfo.appVersion,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );
  }
}
