# Peckish

**Feed the week.** The family food app: a recipe box, a weekly dinner plan,
the grocery list that writes itself from the plan, and a quiet one-tap food
diary for anyone in the house who wants their own numbers.

Local-first and offline by design: the food database — 13,652 USDA foods with
household portions — is **bundled with the app**, so search, logging,
planning, and the grocery list all work with zero network. No accounts, no
ads, no tracking, no subscriptions.

## What it does

- **Recipe box** — paste a link and the page becomes a recipe
  (schema.org/JSON-LD extraction, preview-then-confirm), or write one down.
  Per-serving nutrition appears when the site published it; otherwise the
  recipe simply has no numbers, which is fine.
- **The week** — plan dinners onto seven plates; "Leftovers" and "Out" are
  first-class plans. A renamed recipe renames on the calendar.
- **Groceries** — "Set the table" turns the visible week into an
  aisle-sorted list. Manual adds always survive regeneration; checked items
  are never re-added; unchecked generated lines follow the plan.
- **Today** — a one-tap diary built around your regulars: recents rail,
  saved meals, offline search over the bundled spine, quick add. Static
  targets if you want them; plain numbers either way.
- **Your data is yours** — encrypted `.ohbk` backup/restore (sanctuary),
  plain-JSON export, and a real erase button.

## The network, exactly

The app touches the network only when you act: fetching the one recipe URL
you pasted, optional downloads (an on-device AI model, the offline barcode
databases), and — when a scanned barcode isn't in your phone's databases —
an Open Food Facts lookup that runs only when you tap "Ask
openfoodfacts.org". With the offline database installed, a scan is answered
on the phone and nothing leaves. Everything else is on-device, forever. The
full map lives in-app: Settings → What leaves your device.

## Building

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build web --release   # or: flutter build apk --release
```

Sibling path dependencies (`../packages/sanctuary_auth_core`,
`../packages/sanctuary_backup_ui`, `../packages/oh_fleet_conformance`,
`../ohStyle/openhearth_design`) follow the OpenHearth monorepo layout — see
`.github/workflows/ci.yml` for the clone-siblings recipe.

## Data

Generic-food nutrition: [USDA FoodData Central](https://fdc.nal.usda.gov/)
(public domain, CC0) — Foundation Foods + SR Legacy + FNDDS survey foods,
distilled to a 2.4MB bundled asset. Regeneration recipe in `tool/usda/`.

Peckish is not medical or dietary advice.

## License

MIT — see [LICENSE](LICENSE).
