# The permission surface

The Android manifest declares exactly two permissions:

| Permission | Why |
|---|---|
| `android.permission.INTERNET` | Only when you act (the full map is in-app: Settings → What leaves your device): fetching the one recipe URL you pasted, the optional model and offline-barcode-database downloads, household sync on your own Wi-Fi, an AI guess via your home stove — encrypted to your own machine, only when you ask — and, when a scan misses the offline databases, an Open Food Facts lookup that runs only when you tap "Ask openfoodfacts.org" and sends only the barcode string. |
| `android.permission.CAMERA` | One flow only: the barcode scan screen (v0.2). Runtime permission, requested when you open it. Frames are decoded on the device and discarded — with the offline database a scan usually leaves nothing at all, and the digits only go to Open Food Facts when you ask (v0.7, ADR-0010). |

Everything else — food search, logging, planning, the grocery list, backup
to a local file — is on-device. The surface is enforced by
`test/fleet_conformance_test.dart` (C4, both directions, source + release
merged manifest), so a plugin quietly injecting a permission fails the
build.

That enforcement caught one (v0.3): the camera plugin's own manifest ships
`RECORD_AUDIO` (video capture) plus the legacy storage permissions. Peckish
records nothing and picks photos through the system picker, so the app
manifest strips all three at merge time with `tools:node="remove"` — the
shipped APK asks for exactly the two permissions above.

The web build has no camera scanning (the scanner is FLOSS zxing-cpp via
FFI, deliberately chosen over Google's ML Kit); there you type the digits
printed under the bars instead. Web also has no offline database
(ADR-0010) but keeps the same consent shape: the lookup runs only from the
explicit "Ask openfoodfacts.org" tap, into the same confirm sheet.
