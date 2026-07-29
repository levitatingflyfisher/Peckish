# Changelog

## 0.5.0 — the on-device release

Two new rungs that run entirely on the phone, ported from the fleet's
proven spines (StillLife's CV, Reckon's local LLM). Both optional;
everything else works exactly as before without them.

- **Snap your plate.** A photo button on the guess sheet (Android): the
  on-device classifier labels the plate and the labels become draft
  lines through the bundled USDA food spine — real macros at real
  portions, the classifier's honest confidence, no network, no model
  download, no AI setup. Labels are hand-mapped or skipped, never
  guessed; a photo with nothing edible is a calm state.
- **"On this phone."** The AI guesstimate can now run a small downloaded
  model (Qwen 2.5, 0.5B default / 1.5B option — Apache-2.0, from the
  trusted litert-community org, no account or token) fully offline: not
  one word leaves the device. Settings gains a small model manager —
  download once (resumable, survives sleep and failed attempts), pick,
  delete. Choosing the backend is the opt-in.
- The guess sheet's tile now appears on plate-capable devices even with
  no AI configured — the photo rung never needed the opt-in.
- Android floor rises to 7.0 (minSdk 24, the MediaPipe requirement).

## 0.4.0 — the targets release

Goals, graphs, and the card that helps you finish the day.

- **Daily targets, finally settable.** The targets table shipped in v0.1
  with no editor at all (only backup restore ever wrote it). Settings ›
  Your day now has the editor — four optional numbers, each with a role:
  About (land near), At least (a floor), Under (a budget). The defaults
  say what most people mean — protein is a floor, everything else is
  about — so the minimal setup is typing two numbers. Today's totals
  wear the roles: floors read ≥, caps read ≤.
- **"Round out your day."** With targets set, Today can suggest small
  combinations of your own regulars that finish the day — scored so a
  floor only counts when you're short and a cap only when you'd go
  over, favoring foods you actually eat, each idea one tap to log. A
  finished day gets one warm line; a day nothing helps gets silence,
  never a scold. Master switch in Settings; dismissing hides it for the
  day. All math on-device, deterministic, microseconds.
- **History.** The answer to "what happens tomorrow?" — nothing
  disappears. Today's app bar opens the week as seven calm bars with
  your kcal target as a named line, averages over the days you actually
  logged, and a fortnight of day rows, each opening that day's plate.
  Blank days stay visibly blank — never fake zeros.
- **Tap a line to fix it.** Any logged line (Today or a past day) opens
  an edit sheet. Changing the qty rescales the numbers from the line's
  own per-unit shape; a typed number always wins. Edits heal the
  regulars snapshot without inflating use counts.
- **Back buttons work everywhere.** Settings and About were *replacing*
  the screen stack instead of stacking on it — no back arrow, and
  Android's back button exited the app. Both now push properly.
- Fixed: every sync-stamped write was broadcast as a "preferences
  changed" event (the sync clock shares the prefs table), re-rendering
  prefs watchers app-wide mid-write. Clock writes are silent now.

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
