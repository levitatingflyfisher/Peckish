# Changelog

## Unreleased

- **Ask the household stove.** Settings → AI gains a third place for the
  guess to think: a model running on your own desktop, reached over an
  encrypted channel keyed by the same household phrase you use for
  backups. The phone's small parser gives up on rambling meals; the
  desktop's larger one doesn't — and the honest privacy answer is
  unchanged, because nothing left the house.

## 0.7.1 — the potato pass

No new features — the same app, faster, smaller, and truer, tuned to
run well on a modest phone.

- **Boots faster, every time.** The app no longer re-reads its bundled
  food database on every launch (that was hundreds of milliseconds of
  freeze, forever). The diary and portion lookups gained indexes, so
  the app stays quick as your history grows.
- **Search feels calmer.** Typing in the food search no longer races
  itself on every keystroke; results settle instead of flickering.
- **The chart tells the truth.** A day logged exactly at your target
  now sits exactly on the target line (bars drew slightly low before).
  The axis picker also survives very large system font sizes.
- **Downloads are sturdier.** Leaving a download screen now truly
  pauses the transfer (before, a hidden transfer could keep running and
  a later Resume could corrupt it); a checksum failure explains itself
  instead of reading like a Wi-Fi drop; an install interrupted at the
  last moment resumes without re-downloading; and two downloads at once
  keep the screen awake for as long as either needs it.
- **Restore is exact.** Items you'd deleted from the plan or grocery
  list no longer reappear when restoring a backup.
- **Smaller.** The app shed dead code and an unused icon font — the
  APK is smaller than last release, and the web app loads less.

## 0.7.0 — barcode sovereignty

Scans are answered by your phone. The network became a question.

- **Offline barcode databases.** Settings → Offline barcode lookup
  offers two downloads: US packaged foods from USDA (440,275 barcodes,
  22 MB, public domain) and an optional Open Food Facts US slice
  (927,505 products, 47 MB, ODbL — its attribution travels inside the
  file). Each is verified against a published checksum before install.
- **A scan never touches the network by itself.** With a database on
  your phone, scans are answered locally — in a dead zone, in airplane
  mode, anywhere. A miss shows one button: "Ask openfoodfacts.org."
  Only that tap sends the digits. The old automatic lookup is gone.
- **Every answer names its source** — from your phone's USDA database,
  from your phone's Open Food Facts slice, or from openfoodfacts.org.
- **The privacy map got truer.** "What leaves your device" now says:
  barcode scans, usually nothing.

## 0.6.0 — the hearth release

Phone-test feedback, all five points.

- **It looks like OpenHearth now.** The damson-plum-on-parchment theme
  is gone. Peckish wears the shared openhearth_design system whole —
  hearth terracotta on warm linen, the ember-family dark theme, the
  fleet's own type and buttons — and a test now forbids raw hex in the
  theme layer. Launcher and web icons re-hued to match.
- **A missed day is fixable.** Every history day has its own + that adds
  to THAT day (quick add, search, portions, saved meals). The sheet says
  which day it's feeding; barcode and AI stay in the present tense.
- **The chart grew up.** Pick an axis — kcal, protein, carbs, fat — and
  the bars, value labels, and the target line (wearing its role mark)
  follow. Every bar opens its day.
- **Honest without Google.** On a phone without Play services the plate
  labeler bows out by name and points at everything that still works —
  which is everything else, including the downloaded on-device model.
  New in Settings: "What leaves your device", the whole network map on
  one screen (most rows say "nothing" — that's why data-off just works).
- **Downloads tell the truth.** An interrupted model download now shows
  "Paused — Resume", and Resume picks up from the same byte (it always
  did; now it says so). Leaving the app pauses a transfer; the progress
  survives on disk.

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
