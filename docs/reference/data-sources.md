# Data sources and licensing

## Bundled

**USDA FoodData Central** (https://fdc.nal.usda.gov/) — public domain, CC0
1.0. Three datasets, distilled by `tool/usda/build_spine.py`:

| Dataset | What | Rows kept |
|---|---|---|
| Foundation Foods (2026-04-30) | lab-analyzed whole foods | 428 |
| SR Legacy (2018-04, final) | the classic generic reference | 7,793 |
| FNDDS survey foods (2024-10-31) | as-consumed mixed dishes | 5,431 |

Per-100g kcal/protein/carb/fat/fiber/sugar/sodium plus 36,669 household
portions. Negative carb-by-difference lab artifacts clamp to zero at import.
USDA requests (does not require) citation; the About screen carries it.

## Offline barcode databases (downloadable — v0.7)

Two separately-downloaded SQLite slices answer barcode scans on the phone
(ADR-0010): a **USDA FoodData Central Branded Foods** slice (CC0 1.0 /
public domain, citation requested) and an optional **Open Food Facts US**
slice (ODbL, attribution + license link carried in the file's own `meta`
table). Source-purity law: the two sources are **never merged** into one
file or table — the query-time fallback chain across separate files is a
Collective Database, which keeps the ODbL obligations pinned to the OFF
file alone. Built by public scripts in `tool/barcode_db/`, published as
release assets, downloaded from github.com only when you tap Download.

## Open Food Facts (live, on explicit ask — v0.7)

A scan that misses the local databases (or a phone without them) never
looks anything up by itself. Only when you tap **Ask openfoodfacts.org**
does one `GET /api/v3/product/{barcode}.json` run, parsed into the confirm
sheet, discarded. The request carries the app-identifying User-Agent OFF
asks integrations to use (`Peckish/x.y (repo URL)` — the app, not a person)
and a field allowlist so only name/brand/nutriments/serving come back. What
you *log* is your own snapshot in your own ledger, like any manual entry.
Product data © Open Food Facts contributors, ODbL — credited on the About
screen and on each answer's source line.

## Deliberately not bundled

**Open Food Facts inside the APK** — ADR-0002's "never bundle OFF" stands
for the app package itself. ADR-0010 refines it: a separately-downloaded,
separately-stored, ODbL-labeled slice file with attribution in its own
`meta` table is the compliant distribution shape; the app and the data
never entangle.

## Site-declared recipe nutrition

Imported recipes carry per-serving nutrition only when the source page
published schema.org values; they are stored as `declared*` fields, never
mixed with computed sums.
