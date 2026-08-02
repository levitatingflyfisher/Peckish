"""Build the Peckish Open Food Facts country slice (ADR-0010).

Input: OFF's official Parquet export (huggingface.co/datasets/
openfoodfacts/product-database, food.parquet) — a local path or an https
URL (duckdb's httpfs fetches only the referenced columns). Output: one
sqlite in the shared slice schema, in its OWN file: the slice is an ODbL
Derivative Database and the meta table carries the attribution + license
link that ODbL pins to the data. Never merge these rows with the USDA
slice (source-purity law, see the ADR).

Usage:
  python3 build_off.py <food.parquet|url> <out.sqlite> \
      [--country en:united-states]
"""

import argparse
import datetime
import os
import sqlite3
import sys

import duckdb

from build_usda import normalize_barcode

ATTRIBUTION = (
    "Contains information from Open Food Facts (openfoodfacts.org), "
    "made available under the Open Database License (ODbL).")
LICENSE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"

KJ_PER_KCAL = 4.184
FETCH = 20_000

# The whole extraction stays in duckdb: name preference en → main → first
# entry, labeled kcal preferred over a kJ-only label, macros per 100g.
_QUERY = """
SELECT code,
       COALESCE(
         list_transform(list_filter(product_name, x -> x.lang = 'en'),
                        x -> x."text")[1],
         list_transform(list_filter(product_name, x -> x.lang = 'main'),
                        x -> x."text")[1],
         product_name[1]."text") AS name,
       brands,
       list_transform(list_filter(nutriments, x -> x."name" = 'energy-kcal'),
                      x -> x."100g")[1] AS kcal_100g,
       list_transform(list_filter(nutriments, x -> x."name" = 'energy'),
                      x -> x."100g")[1] AS energy_kj_100g,
       list_transform(list_filter(nutriments, x -> x."name" = 'proteins'),
                      x -> x."100g")[1] AS protein_100g,
       list_transform(list_filter(nutriments, x -> x."name" = 'carbohydrates'),
                      x -> x."100g")[1] AS carb_100g,
       list_transform(list_filter(nutriments, x -> x."name" = 'fat'),
                      x -> x."100g")[1] AS fat_100g,
       TRY_CAST(serving_quantity AS DOUBLE) AS serving_g,
       serving_size
FROM read_parquet(?)
WHERE list_contains(countries_tags, ?)
  AND (obsolete IS NULL OR NOT obsolete)
  AND code IS NOT NULL
"""


def build_slice(parquet, out_path, country_tag):
    if os.path.exists(out_path):
        os.remove(out_path)
    dcon = duckdb.connect()
    if parquet.startswith(("http://", "https://")):
        dcon.execute("INSTALL httpfs; LOAD httpfs;")

    scon = sqlite3.connect(out_path)
    scon.execute("PRAGMA journal_mode=OFF")
    scon.execute("PRAGMA synchronous=OFF")
    scon.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    scon.execute("""CREATE TABLE products(
        barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT,
        kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL,
        serving_g REAL, serving_label TEXT)""")

    cursor = dcon.execute(_QUERY, [parquet, country_tag])
    total = 0
    while True:
        chunk = cursor.fetchmany(FETCH)
        if not chunk:
            break
        rows = []
        for (code, name, brands, kcal, kj, protein, carb, fat,
             serving_g, serving_label) in chunk:
            barcode = normalize_barcode(code)
            if barcode is None or not name or not name.strip():
                continue
            if kcal is None and kj is not None:
                kcal = kj / KJ_PER_KCAL
            rows.append((barcode, name.strip(),
                         brands.strip() if brands and brands.strip() else None,
                         kcal, protein, carb, fat, serving_g,
                         serving_label.strip()
                         if serving_label and serving_label.strip() else None))
        scon.executemany(
            "INSERT OR REPLACE INTO products VALUES (?,?,?,?,?,?,?,?,?)", rows)
        total += len(rows)
        if total % 200_000 < FETCH:
            print(f"    …{total:,} rows", file=sys.stderr)

    count = scon.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    meta = {
        "format_version": "1",
        "source": "off",
        "license": "ODbL-1.0",
        "license_url": LICENSE_URL,
        "attribution": ATTRIBUTION,
        "built_at": datetime.date.today().isoformat(),
        "product_count": str(count),
        "source_release": datetime.date.today().isoformat(),
        "country": country_tag,
    }
    scon.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    scon.commit()
    scon.execute("VACUUM")
    scon.close()
    dcon.close()
    print(f"  {count:,} products → {out_path}", file=sys.stderr)
    return out_path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("parquet", help="food.parquet path or https URL")
    ap.add_argument("out")
    ap.add_argument("--country", default="en:united-states")
    args = ap.parse_args()
    build_slice(args.parquet, args.out, country_tag=args.country)


if __name__ == "__main__":
    main()
