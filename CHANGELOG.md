# Changelog

## 0.9.1 — nothing you typed gets thrown away

- **A stray tap no longer discards a form.** Swipe over to another app to
  read a number off a photo, swipe back, and Android does not bring the
  keyboard with it — so the sheet shrinks and the field you had already
  aimed at moves. The tap lands on the dimmed background and used to take
  the whole entry with it. Every screen that holds something you typed now
  ignores that tap and shows an **×** instead. Dragging the sheet down and
  the back button still close it, and a confirmation — which holds nothing
  you typed — still closes when you tap away, because that is the right
  gesture for "never mind".

## 0.9.0 — the second-tap release

0.8 made every past day *reachable*. This one makes the things you do
there cost what they should — usually one tap — and fixes what a phone
test found once the screens were being used in earnest.

- **The food you always eat is one tap on every day.** Your regulars sit
  on Today, on any past day, and at the top of the **+** sheet, above
  quick add and the scanner — each aimed at the day it was opened on.
  Filling a gap in last week used to mean typing a search, the slowest
  route in the app for the food you eat most.
- **History is a tab.** The month you just lived is the second-most
  looked-at screen in the app; it was an icon in the corner beside
  Settings, which is where things go to be forgotten.
- **A past day shows its own four numbers.** The same kcal figure and
  per-macro breakdown Today shows, against the same targets — so you can
  read exactly what you ate on the 19th instead of inferring it from a
  dot on a chart.
- **A food you saved answers its own barcode.** Ticking "Save to My
  Foods" now brings the code home with the food, so scanning that tin
  again logs it straight away — no confirm sheet, no lookup, and the
  network is never asked a question the phone already answered.
- **One scan screen, and the camera stands down.** The Scan/Type toggle
  is gone: the digits field was always live in camera mode, so
  remembering a preference could only ever cost you a click. The camera
  now switches itself off the moment there is something to deal with — a
  lookup running, a question to answer, the confirm sheet open — and
  shows the digits it read instead, which a photo picked from the gallery
  never had.
- **The month arrows stay put** while the month scrolls under them, so
  they are still there when you have reached the calendar.
- **Targets stopped printing as boxes.** Peckish bundles its own type and
  neither font has ≥ or ≤, so every target anyone ever set rendered a
  tofu box: "of □2200 kcal". Caps read "max" and floors "min" now, in
  letters the fonts actually have.
- **Numbers stop being sheared** at large accessibility text sizes: the
  day's total no longer splits across two lines, and a macro label no
  longer loses its target off the right-hand edge.

## 0.8.0 — the missed-day release

Every way of logging now works on a day you already lived, and history
finally looks like something you can reach into.

- **A scan can fix yesterday.** Barcode, the AI guess, and the plate
  photo all work from a past day's **+** — the sheet names the day it's
  feeding before you confirm. v0.6 hid these on past days as "now-flows";
  that was wrong, since the tin still in your recycling is the best record
  you have of the day you forgot to log.
- **History is a month you can read.** A trend line for the macro you
  pick, with your target ruled across it — a gap in the line is a day you
  didn't log, never a zero. Under it, a real calendar: every past day is a
  tappable cell showing that day's number, and the heading says out loud
  that tapping is how you fix a day. Arrows walk back through the months.
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
