# AGENTS.md — working on Peckish

Peckish is the OpenHearth family food app: recipe box + weekly plan +
self-writing grocery list + one-tap diary, local-first, no accounts.
Android applicationId/namespace: **com.openhearth.peckish** (from commit 1 —
never `com.example`).

## Read first

README → VISION (the one idea + honest scorecard) → this file →
docs/README.md (Diátaxis hub). Decisions live in docs/adr/.

## Map

- `lib/core/` — providers (all repositories + `spineReady` boot import),
  router (4-tab shell: Today/Plan/Recipes/Groceries), drift `AppDatabase`.
- `lib/features/food/` — `MacroSet` (null = unknown, never zero), the
  bundled-USDA repository (import/search/portions), custom foods.
- `lib/features/diary/` — the ledger (snapshot macros at log time), saved
  meals (one-tap `logMeal`), static targets, Today UI + add sheet.
- `lib/features/recipes/` — box CRUD, schema.org parser, fetcher, UI.
- `lib/features/plan/` — week cells (recipe/meal/note; titles resolve live).
- `lib/features/groceries/` — the list + its three regeneration laws +
  keyword aisle classifier.
- `lib/features/sanctuary_backup/` + `lib/features/settings/` — .ohbk wiring
  (PeckishExport is the single wire shape), export/erase.
- `assets/food/usda_foods.json` — the bundled spine (regenerate via
  `tool/usda/`, see its README for the FNDDS nutrient-id gotcha).

## Non-negotiables

- **The growth law:** any new user-data table joins, in the SAME commit:
  `AppDatabase.eraseUserData`, `PeckishExport` (sections), the backup
  serializer, and the restore-consequence copy — which is TEST-BOUND
  (backup_serializer_test) to name everything erase wipes.
- **Null is unknown, never zero.** Day totals fold from the all-null set;
  a kcal-only day reports protein as unknown. Don't "fix" this.
- **Ledger snapshots.** Diary entries carry their own macros; editing or
  deleting a food/recipe/meal never rewrites history.
- **Two-tap law + thumb targets.** Regulars log in one tap; every top-level
  screen must pass the 320dp / 2× textScale sweep
  (test/shared/accessibility_sweep_test.dart).
- **Network = two user-initiated flows only** (recipe-URL fetch, OFF barcode
  lookup). INTERNET is the only manifest permission; the conformance test
  records the surface.
- **Storage enums** (`FoodKindDb` etc.) are separate from domain enums so a
  reorder can't rewrite stored integers. Append only.
- Wire schemaVersion (PeckishExport, hardcoded 1) ≠ drift schemaVersion.
  Additive JSON keys never bump the wire version.

## How to work

TDD (tests exist for every layer — copy their patterns), atomic commits
stating the why, `dart run build_runner build --delete-conflicting-outputs`
after schema/provider changes, `flutter analyze` clean, full `flutter test`
before pushing. CI clones the sibling packages by path — see
.github/workflows/ci.yml.
