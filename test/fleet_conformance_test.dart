import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

void main() => runFleetConformance(const FleetAppConfig(
      appId: 'peckish',
      // Tier-T (zero visual change): only the Material TextTheme ladder comes
      // from openhearth_design; the jam/oat/butter identity stays app-local.
      // None of those hex values coincide with canonical tokens, so no
      // allowedTokenLiterals are needed.
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
