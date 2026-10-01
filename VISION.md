# Vision

## The one idea

**Nutrition belongs to the household's meals, not to anyone's body.** Every
food app on the market serves a solo dieter; families plan dinners, write
grocery lists, and want to feed themselves well without ceremony. Peckish
pairs the planning (recipes → week → list) with ambient nutrition awareness
(a bundled, offline, public-domain food database) and keeps the personal
diary a quiet optional rung on top — one tap for the people who want their
own numbers, invisible to everyone else.

Two positions no surveyed competitor holds (2026-07 research, adversarially
verified): a food database that actually works offline — every FLOSS tracker
is network-dependent for lookup — and meal planning paired with nutrition in
one local-first, no-accounts app.

## The laws

1. **The daily loop costs at most two taps.** Regulars are one.
2. **Nutrition describes meals.** Weekly dinners are a household fact, not a
   verdict. Advisory, never blocking; clay, never red. (That law is about
   the household's food and numbers. The one irreversible system act, Erase
   all data, uses the fleet's urgency red with its icon and word, per the
   ohStyle colour language: red + icon + word means "this cannot be taken
   back", never "you ate too much".)
3. **Every entity has full CRUD.** Edit, delete, reset, archive — forgiveness
   over prevention applies to data too.
4. **The ledger never rewrites.** Entries snapshot macros at log time.
5. **Unknown is never zero.** A missing number stays missing.
6. **Targets are static.** They change when you change them. (The schema
   keeps timestamps and static fields; an adaptive loop remains a deliberate
   ~50-line non-feature.)

## Honest scorecard

| Claim | Status |
|---|---|
| Offline food search over 13,652 USDA foods | **Shipped** — bundled CC0 spine, version-stamped import |
| Recipe box with paste-a-URL import | **Shipped** — generic schema.org extractor; per-site long tail NOT covered (recipe-scrapers has 649 subclasses for a reason); manual entry is the honest fallback, offered in place when a fetch fails (the failure is a plain sentence under the link, never the raw error). The editor keeps a draft as you type, so leaving it loses nothing |
| Weekly plan + self-writing grocery list | **Shipped** — three regeneration laws, keyword aisle sort (deliberately dumb, user-correctable); Set the table is pinned under the week and offered from an empty list; a planned recipe shows its kcal per serving. Today's planned recipe or staple has a **Log this** (one serving, or every item of the staple, with the lasting Undo): the plan reaches the diary only when you say so, never on its own (lens audit finding 4) |
| One-tap diary + staples + targets + history | **Shipped** — target roles (floor / budget / about) with "round out your day" suggestions drawn from your own regulars (v0.4, ADR-0008); a month-shaped history (v0.8) — trend line per macro against its target, tappable calendar, blank days stay visibly blank; a day's own lines show all four macros, not kcal alone |
| Fixing a day you already lived | **Shipped v0.8, made cheap in v0.9, made findable since** — every way in (Find food, Quick add, Scan, Type a code, Guess it) lives on a speed-dial in the thumb zone, each naming the day before it writes; the **Foods** screen behind "See all" is one searchable surface over regulars, My Foods, saved meals, and the offline spine, with honest sort labels instead of three lists that just looked unsorted |
| Forgiveness over prevention, for real | **Shipped** — the law was stated in this document before the code kept it. A swipe (diary line, grocery item) asks first, naming the thing; a deliberate delete (a recipe, a custom food, a planned meal, "Clear checked", Delete in a line's sheet) does not ask and offers an Undo that never times out: it stays under every screen until you tap it, dismiss it, or delete something else (fleet delete ruling, `shared/widgets/undo_host.dart`). Logging a regular offers Undo too. No redo stack: a redo without a visible history surface would be guesswork UX. Downloaded model and barcode files still ask before they go, since no soft delete can hold a gigabyte |
| A scan you have already answered | **Shipped v0.9** — saving a scanned food keeps its barcode (normalized per ADR-0010), so the resolver answers off your own shelf before any slice and logs at the serving you chose. The network is never asked twice |
| Encrypted backup / restore (.ohbk) | **Shipped** — sanctuary spine, consequence copy test-bound to the erase set |
| Ingredient→food matching for computed recipe nutrition | **Schema shipped, UI minimal** — declared (site) nutrition works today; hand-matching lines is future polish |
| Family shared plan/groceries across devices | **Shipped v0.2 (LAN)** — encrypted Wi-Fi pairing, HLC last-write-wins with tombstones (ADR-0006); diaries and targets never leave a device. Internet sync (CRDT over a blind relay) remains not built |
| Barcode scanning (offline-first) | **Shipped v0.7** — camera scan + typed digits, answered from downloadable USDA/OFF database slices on the phone (ADR-0010); the network is a question — one Open Food Facts lookup per explicit "Ask openfoodfacts.org" tap |
| AI meal guesstimate (on-phone / household stove / BYOK) | **Shipped** — BYOK v0.2, fully on-device model v0.5 (Qwen via flutter_gemma, ADR-0009), and the **household stove**: the same ask answered by a far larger model on the family's own desktop, over domovoi's encrypted protocol keyed by the household phrase. The parser drafts and you confirm — every logged line carries `ai` provenance |
| Plate photo → draft lines (on-device CV) | **Shipped v0.5** — ML Kit labeler, Android; labels are hand-mapped through the bundled spine or skipped, never guessed |
| iOS | Not planned (fleet convention: Android + PWA) |
