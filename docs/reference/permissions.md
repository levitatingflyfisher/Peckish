# The permission surface

The Android manifest declares exactly one permission:

| Permission | Why |
|---|---|
| `android.permission.INTERNET` | Two user-initiated flows only: fetching the one recipe URL you pasted, and (future) an Open Food Facts barcode lookup that sends only the barcode string. |

Everything else — food search, logging, planning, the grocery list, backup
to a local file — is on-device. The surface is enforced by
`test/fleet_conformance_test.dart` (C4, both directions, source + release
merged manifest), so a plugin quietly injecting a permission fails the
build.
