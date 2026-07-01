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
   verdict. Advisory, never blocking; clay, never red.
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
| Recipe box with paste-a-URL import | **Shipped** — generic schema.org extractor; per-site long tail NOT covered (recipe-scrapers has 649 subclasses for a reason); manual entry is the honest fallback |
| Weekly plan + self-writing grocery list | **Shipped** — three regeneration laws, keyword aisle sort (deliberately dumb, user-correctable) |
| One-tap diary + staples + static targets | **Shipped** |
| Encrypted backup / restore (.ohbk) | **Shipped** — sanctuary spine, consequence copy test-bound to the erase set |
| Ingredient→food matching for computed recipe nutrition | **Schema shipped, UI minimal** — declared (site) nutrition works today; hand-matching lines is future polish |
| Family shared plan/groceries across devices | **Not built** — v0.1 is single-device; the researched path is CRDT (tudo-pattern sqlite_crdt) over a blind relay, LAN-first |
| Barcode scanning (Open Food Facts) | **Not built** — designed for (INTERNET permission + terms reviewed), deliberately after v0.1 |
| AI meal guesstimate (local model / BYOK) | **Not built** — Reckon's spine is the template when it earns its place |
| iOS | Not planned (fleet convention: Android + PWA) |
