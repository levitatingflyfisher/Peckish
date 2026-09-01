import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:peckish/core/providers/core_providers.dart';

/// Light, dark, or follow the phone, from any tab's top bar (fleet theme
/// ruling: at most two taps from anywhere). Icon plus a short word; the
/// menu names all three choices.
class ThemeToggleAction extends ConsumerWidget {
  const ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(userPrefsProvider).value?.themeMode ??
        OhThemeModePreference.defaultValue;
    // The label stops growing at 2x text so the bar still fits at 320dp
    // (see BarActions); the page itself scales fully.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2.0,
      child: OhThemeToggle(
        value: mode,
        onChanged: (next) =>
            ref.read(settingsRepositoryProvider).setThemeMode(next),
      ),
    );
  }
}
