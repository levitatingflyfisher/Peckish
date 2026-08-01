# ADR-0010 — Offline barcode databases; the network becomes a question

**Status:** accepted · 2026-08-01 · amends ADR-0002's barcode posture

## Context

v0.6 shipped with one honesty gap the privacy screen made visible: every
barcode scan sent the GTIN to a third party (Open Food Facts) and was dead
offline. Adversarially-verified research (2026-07, ~100-agent verification
run + manual primary-source checks) established two independently viable
offline solutions:

**USDA FoodData Central "Branded Foods"** — `branded_food.csv` carries a
`gtin_upc` column (the barcode as lookup key) for ~1.9M US packaged foods.
License: CC0 1.0 / public domain — citation *requested*, not required
([FDC data dictionary](https://fdc.nal.usda.gov/portal-data/external/dataDictionary),
[Ag Data Commons](https://data.nal.usda.gov/dataset/fooddata-central-0)).
~430MB zipped CSV at source, refreshed roughly every 6 months, US-centric.

**Open Food Facts bulk exports** — official daily pipeline: nightly
JSONL/CSV dumps plus an OFF-maintained Parquet on Hugging Face
(`openfoodfacts/product-database`, ~7.8GB / 4.7M products), with 14-day
~21MB/day deltas ([off data page](https://world.openfoodfacts.org/data)).
Licensing mechanics (all 3-0 verified): a filtered slice is an ODbL
**Derivative Database** — it stays ODbL with attribution + license link
attached **to the data file**; the MIT app is protected twice over, by
§4.5(a)'s collective-database carve-out and §2.3's exclusion of computer
programs (the OSMF-board-endorsed reading; persuasive, not case law).
Product **images are CC-BY-SA and are excluded**. The "Produced Work"
escape for database files was refuted 0-3.

Killed in verification (open questions, not evidence): prior-art offline
modes in other apps, k-anonymity/PIR lookup APIs, LAN-mirror sizing.

## Decision

1. **Two downloadable slices, never bundled, never merged.** A USDA
   Branded slice (default recommendation) and an optional OFF
   US-country slice, each a separate SQLite file built by public scripts
   in `tool/barcode_db/` and published as release assets. **Source-purity
   law: OFF rows are never merged into the same table/file as USDA rows.**
   A query-time fallback chain across separate databases is a Collective
   Database and keeps the ODbL obligations pinned to the OFF file alone.
   This *refines* ADR-0002: "never bundle OFF" stands for the APK; a
   separately-downloaded, separately-stored, ODbL-labeled file with
   attribution in its own `meta` table is the compliant distribution shape.
2. **Lookup chain: local USDA → local OFF → a question.** A scan that
   misses locally never touches the network by itself. The miss state
   offers an explicit "Ask openfoodfacts.org" action — one tap, one GET,
   per scan — and points at the offline download. This replaces
   ADR-0002's "1 API call = 1 real scan" as the default with "0 API calls
   unless the user says so."
3. **Normalization law**: barcodes are stored and queried as digit strings
   with leading zeros stripped (UPC-A vs EAN-13 zero-padding collapses to
   one key). Checksum validation stays at the input boundary
   (`BarcodeCode`).
4. **Transfer discipline**: the download mirrors the model downloader
   (Range resume, `.part`, atomic rename = completeness proof) plus a
   SHA-256 check of the compressed artifact before decompression —
   reference data that steers meals earns an integrity check.
5. **Web stays online-only** (no local slice), but gets the same consent
   shape: the lookup is an explicit action, never automatic.

## Consequences

- A scan in a dead zone works; a scan on data reveals nothing unless the
  user chooses to ask. The privacy screen's barcode row becomes "usually
  nothing".
- The OFF slice file, its builder, and its ODbL attribution ship publicly
  (release assets + `tool/barcode_db/`), which *is* the ODbL compliance:
  the derivative database is available under ODbL with the alteration
  method alongside.
- Refresh is manual and roughly twice a year: re-run the builders, upload
  new dated assets, bump the in-app catalog. `meta.built_at` keeps the
  staleness visible in the UI.
- Nutrition basis is per-100g/100ml as published upstream (beverages are
  per-100ml in both sources); the app treats them uniformly, as it
  already does for OFF network answers.
