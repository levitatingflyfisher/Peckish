# Regenerating the offline barcode databases

The two downloadable slices behind Settings → Offline barcode lookup
(ADR-0010). Each builder distills a public bulk release into a small
SQLite file: `barcode → name/brand/serving/per-100g macros`, plus a
`meta` table carrying the source, release date, and license.

- `build_usda.py` — USDA FoodData Central **Branded Foods** bulk CSV
  (public domain, CC0). The CSVs are multi-GB, so the join runs staged
  through a scratch SQLite database, not in memory.
- `build_off.py` — the **Open Food Facts** parquet dump (ODbL), filtered
  to US-sold products via DuckDB. The ODbL attribution and license link
  are written into the file's own `meta` table — attribution travels
  with the data, not with the app.

**The source-purity law:** the two sources are never merged into one file
or table. The app's query-time fallback chain across separate files is a
Collective Database under ODbL — keeping OFF's obligations pinned to the
OFF file alone. If you change these builders, keep that separation.

Ship shape: each slice is gzipped and published as a dated asset on the
`v0-data` release; its SHA-256 is pinned in
`lib/features/barcode/data/barcode_db_spec.dart`, and the app verifies
the checksum before install. Publishing a refreshed slice therefore
means: run the builder, upload the .gz, update the spec's hash + size +
date, ship an app update.

Both builders have tests (`test_build_*.py`) over miniature fixture
inputs — run them before publishing anything.
