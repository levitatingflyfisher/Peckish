# Changelog

## 0.3.0 — the regulars release

Every bug from the first phone test, fixed:

- **Quick add takes all four numbers** — kcal, protein, carbs, and fat are
  each enterable (none required), and "Remember this food" turns the line
  into a custom food that search finds next time. Cancel now returns to the
  + sheet instead of closing it.
- **Regulars survive diary editing.** The one-tap rail used to be derived
  from live diary rows, so deleting a day's entries erased the habits it
  showed. Regulars are now their own persistent record (use counts + newest
  snapshot), backfilled from your existing diary on update, included in
  backups/exports, and never synced.
- **A Foods screen behind the rail** ("See all"): browse regulars with use
  counts, hide ones you're done with (logging them again brings them back),
  and manage My Foods with full CRUD — edit in place, rest, delete.
- **Barcode scanning actually recognizes.** The camera now decodes with the
  detector's try-harder/rotate/inverted/downscale passes on retail (1D)
  formats, scans more of the frame, twice as often — plus a flash button
  and a pick-a-photo fallback. Scanning a code twice can no longer stack
  two confirm sheets, and logging from the sheet returns you home.
- **Type it without the camera.** A Scan/Type toggle (remembered) keeps the
  camera off when you'd rather type, with a sketch showing that the small
  digits at the ends of the barcode count too.
- The APK now asks for exactly INTERNET + CAMERA: the camera plugin's
  RECORD_AUDIO and legacy storage permissions are stripped at merge time.
- Fixed: a failed secure-storage read could crash the + sheet instead of
  simply hiding the AI tile.

## 0.2.0 — scan, guess, and the household kitchen

(Section written retroactively in 0.3.)

- **Barcode scan** (Android camera; typed digits everywhere): checksum-
  validated GTIN → one Open Food Facts lookup → confirm-before-log with
  editable grams and "Save to My Foods". CAMERA joined the permission
  surface.
- **AI guesstimate** (ships off; BYOK Claude key or any OpenAI-compatible
  local endpoint): describe the meal, prune the drafted lines, confirm.
  The parser never writes the ledger directly; every logged line carries
  `ai` provenance.
- **Household LAN sync** — "the kitchen is shared, the plate is yours":
  recipes, plan, groceries, custom foods, and saved meals sync over an
  encrypted LAN pairing (HLC last-write-wins with tombstones); diaries and
  targets never leave the device.
- Fixed: the plain-JSON export wrote an empty file in 0.1.

## 0.1.0 — first release

The family food app, whole: recipe box with paste-a-URL import
(schema.org, preview-then-confirm), the week of plates with first-class
Leftovers, the grocery list that writes itself from the plan (manual adds
survive, checked items never re-add, aisle-sorted), and the one-tap diary —
recents rail, saved meals, quick add, static targets.

Offline by construction: 13,652 USDA foods (Foundation + SR Legacy + FNDDS,
public domain) with 36,669 household portions bundled as a 2.4MB asset —
search and logging never touch the network. INTERNET is declared for exactly
one shipped flow: fetching a recipe URL you pasted.

Encrypted `.ohbk` backup/restore on the sanctuary spine, plain-JSON export,
full erase. No accounts, no ads, no tracking, no notifications.
