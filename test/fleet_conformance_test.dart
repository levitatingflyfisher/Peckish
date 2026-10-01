import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

void main() => runFleetConformance(const FleetAppConfig(
      appId: 'peckish',
      // Draws in openhearth_design's package fonts (bundled, never
      // fetched), so nothing falls back to a web font: a character those
      // families cannot draw is a box on a real phone. C7 (0.8.1 counts
      // package fonts) sweeps lib/ for any.
      // C8: Peckish themes from OhTheme.light()/hearthDark(), whose
      // app-wide iconTheme overrides a filled icon button's own foreground
      // — which is how the snap-your-plate camera glyph ended up painted
      // in primary against its tonal fill. Guard stays on.
      checks: {
        // C13: the PWA loads nothing from Google's CDNs. web/flutter_bootstrap.js
        // points CanvasKit and the engine's fallback fonts at this origin.
        FleetCheck.c13WebSelfHosted,
        ...FleetAppConfig.withBundledFonts,
        FleetCheck.c8IconButtons,
        // C10: no raw exception text on screen. Failures are a sentence
        // (the recipe import names what went wrong; ohFriendlyErrorMessage
        // for the rest) and the raw error goes to the log.
        FleetCheck.c10RawErrors,
        // C11: every app-bar action carries a word. C11's floor is a
        // tooltip; test/shared/widgets/top_bar_words_test.dart holds the
        // ruling itself (a visible word, never an icon alone).
        FleetCheck.c11IconLabels,
        // C9: every routed screen has a way in.
        FleetCheck.c9Routes,
        // Item 24: the screens below are swept at 360dp × 1.3 (and 320dp ×
        // 3.0) in test/a11y/primary_action_sweep_test.dart.
        FleetCheck.c5PrimaryScreens,
        // C12: the accent (OhTheme's warmth, no appAccent) must not be
        // mistaken for the error red.
        FleetCheck.c12AccentVsError,
      },
      primaryActionScreens: {
        'TodayScreen',
        'PlanScreen',
        'GroceriesScreen',
        'RecipesScreen',
        'RecipeEditScreen',
      },
      // Tokens tier: Peckish wears OhTheme.light()/hearthDark() whole, and
      // every app colour is an alias onto OhColors (app_colors.dart), so no
      // raw hex lives in lib/ and no allowedTokenLiterals are needed.
      styleTier: StyleTier.tokens,
      // The exact manifest surface — INTERNET for the two user-initiated
      // network flows (paste-a-recipe-URL fetch, OFF barcode lookup), CAMERA
      // for the one scan screen (v0.2, runtime-requested there). The bundled
      // food database keeps everything else offline.
      androidPermissions: {
        'android.permission.INTERNET',
        'android.permission.CAMERA',
      },
      // C4 v2 — the release MERGED surface: source permissions plus what
      // plugins and the manifest merge inject. Recorded from the first real
      // APK build's findings (the C4 recipe); bites on the dev box whenever
      // a merged manifest exists under build/.
      mergedAndroidPermissions: {
        'android.permission.INTERNET',
        'android.permission.CAMERA',
        'com.openhearth.peckish.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
      },
    ));
