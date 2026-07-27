# The permission surface

The Android manifest declares exactly two permissions:

| Permission | Why |
|---|---|
| `android.permission.INTERNET` | Two user-initiated flows only: fetching the one recipe URL you pasted, and an Open Food Facts barcode lookup that sends only the barcode string. |
| `android.permission.CAMERA` | One flow only: the barcode scan screen (v0.2). Runtime permission, requested when you open it. Frames are decoded on the device and discarded — only the digits ever leave, and only to Open Food Facts. |

Everything else — food search, logging, planning, the grocery list, backup
to a local file — is on-device. The surface is enforced by
`test/fleet_conformance_test.dart` (C4, both directions, source + release
merged manifest), so a plugin quietly injecting a permission fails the
build.

The web build has no camera scanning (the scanner is FLOSS zxing-cpp via
FFI, deliberately chosen over Google's ML Kit); there you type the digits
printed under the bars instead — same lookup, same confirm sheet.
