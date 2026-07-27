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

## Open Food Facts (live, per-scan — v0.2)

The barcode scan screen looks a product up against the **live** Open Food
Facts API: one user scan = one `GET /api/v3/product/{barcode}.json`, parsed
into the confirm sheet, discarded. The request carries the app-identifying
User-Agent OFF asks integrations to use (`Peckish/x.y (repo URL)` — the app,
not a person) and a field allowlist so only name/brand/nutriments/serving
come back. What you *log* is your own snapshot in your own ledger, like any
manual entry. Product data © Open Food Facts contributors, ODbL — credited
on the About screen.

## Deliberately not bundled

**Open Food Facts as a database** — ODbL share-alike; bundling a derived
database would attach share-alike obligations for no offline benefit (see
ADR-0002). Per-scan live lookup is the compliant shape its terms welcome
("1 API call = 1 real scan by a user").

## Site-declared recipe nutrition

Imported recipes carry per-serving nutrition only when the source page
published schema.org values; they are stored as `declared*` fields, never
mixed with computed sums.
