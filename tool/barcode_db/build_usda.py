"""Build the Peckish USDA Branded barcode slice (ADR-0010).

Input: an unzipped USDA FoodData Central "Branded Foods" CSV directory
(branded_food.csv + food.csv + food_nutrient.csv). Output: one compact
sqlite in the shared slice schema — meta(key,value) + products(barcode PK,
name, brand, per-100g/ml macros, serving). CC0 source; the meta table
carries the requested citation.

Usage:
  python3 build_usda.py <csv_dir> <out.sqlite> --release 2025-12-18
"""

import argparse
import csv
import datetime
import os
import re
import sqlite3
import sys

ATTRIBUTION = (
    "U.S. Department of Agriculture, Agricultural Research Service. "
    "FoodData Central Branded Foods. fdc.nal.usda.gov")

# Energy preference: labeled kcal (1008), then Atwater General (2047),
# then Atwater Specific (2048) — all published in KCAL.
ENERGY_IDS = (1008, 2047, 2048)
MACRO_IDS = {1003: "protein", 1004: "fat", 1005: "carb"}
WANTED_IDS = set(ENERGY_IDS) | set(MACRO_IDS)

# Serving sizes arrive in these mass/volume units; anything else (IU,
# "bar") can't be treated as grams and only the household label survives.
GRAMISH_UNITS = {"g", "grm", "gram", "grams", "ml", "mlt"}

CHUNK = 50_000


def normalize_barcode(raw):
    """Digits only, leading zeros stripped (UPC-A/EAN-13 padding collapses
    to one key). Returns None for inputs with no digits at all."""
    digits = re.sub(r"\D", "", raw or "")
    if not digits:
        return None
    return digits.lstrip("0") or "0"


def _chunked_insert(con, sql, rows_iter):
    batch = []
    total = 0
    for row in rows_iter:
        batch.append(row)
        if len(batch) >= CHUNK:
            con.executemany(sql, batch)
            total += len(batch)
            if total % 2_000_000 < CHUNK:
                print(f"    …{total:,} rows", file=sys.stderr)
            batch.clear()
    if batch:
        con.executemany(sql, batch)
        total += len(batch)
    return total


def _branded_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["market_country"] != "United States":
                continue
            barcode = normalize_barcode(row["gtin_upc"])
            if barcode is None:
                continue
            serving_g = None
            unit = (row["serving_size_unit"] or "").strip().lower()
            if unit in GRAMISH_UNITS:
                try:
                    serving_g = float(row["serving_size"])
                except ValueError:
                    serving_g = None
            brand = (row["brand_name"] or "").strip() \
                or (row["brand_owner"] or "").strip()
            yield (int(row["fdc_id"]), barcode, brand,
                   serving_g, (row["household_serving_fulltext"] or "").strip(),
                   (row["short_description"] or "").strip())


def _food_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["data_type"] != "branded_food":
                continue
            yield (int(row["fdc_id"]), (row["description"] or "").strip())


def _nutrient_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                nid = int(row["nutrient_id"])
            except ValueError:
                continue
            if nid not in WANTED_IDS:
                continue
            try:
                amount = float(row["amount"])
            except ValueError:
                continue
            yield (int(row["fdc_id"]), nid, amount)


def build_slice(csv_dir, out_path, source_release):
    if os.path.exists(out_path):
        os.remove(out_path)
    con = sqlite3.connect(out_path)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")

    con.execute("""CREATE TABLE meta(
        key TEXT PRIMARY KEY, value TEXT NOT NULL)""")
    con.execute("""CREATE TABLE products(
        barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT,
        kcal REAL, protein_g REAL, carb_g REAL, fat_g REAL,
        serving_g REAL, serving_label TEXT)""")

    # Staging tables keep the GB-scale join out of Python memory.
    con.execute("""CREATE TABLE stage_branded(
        fdc_id INTEGER PRIMARY KEY, barcode TEXT, brand TEXT,
        serving_g REAL, serving_label TEXT, short_desc TEXT)""")
    con.execute("CREATE TABLE stage_name(fdc_id INTEGER PRIMARY KEY, name TEXT)")
    con.execute("CREATE TABLE stage_nutr(fdc_id INTEGER, nid INTEGER, amount REAL)")

    print("  branded_food.csv…", file=sys.stderr)
    n = _chunked_insert(con, "INSERT OR REPLACE INTO stage_branded VALUES (?,?,?,?,?,?)",
                        _branded_rows(os.path.join(csv_dir, "branded_food.csv")))
    print(f"  {n:,} US branded rows", file=sys.stderr)

    print("  food.csv…", file=sys.stderr)
    _chunked_insert(con, "INSERT OR REPLACE INTO stage_name VALUES (?,?)",
                    _food_rows(os.path.join(csv_dir, "food.csv")))

    print("  food_nutrient.csv…", file=sys.stderr)
    _chunked_insert(con, "INSERT INTO stage_nutr VALUES (?,?,?)",
                    _nutrient_rows(os.path.join(csv_dir, "food_nutrient.csv")))
    con.execute("CREATE INDEX idx_nutr ON stage_nutr(fdc_id)")

    # Same barcode over the years → ascending fdc_id + OR REPLACE keeps the
    # newest record. Nameless rows (no description, no short description)
    # are useless to the diary and dropped.
    print("  joining…", file=sys.stderr)
    con.execute("""
        INSERT OR REPLACE INTO products
        SELECT b.barcode,
               COALESCE(NULLIF(n.name,''), NULLIF(b.short_desc,'')),
               NULLIF(b.brand,''),
               p.kcal, p.protein, p.carb, p.fat,
               b.serving_g, NULLIF(b.serving_label,'')
        FROM stage_branded b
        LEFT JOIN stage_name n ON n.fdc_id = b.fdc_id
        LEFT JOIN (
            SELECT fdc_id,
                   COALESCE(MAX(CASE WHEN nid=1008 THEN amount END),
                            MAX(CASE WHEN nid=2047 THEN amount END),
                            MAX(CASE WHEN nid=2048 THEN amount END)) kcal,
                   MAX(CASE WHEN nid=1003 THEN amount END) protein,
                   MAX(CASE WHEN nid=1005 THEN amount END) carb,
                   MAX(CASE WHEN nid=1004 THEN amount END) fat
            FROM stage_nutr GROUP BY fdc_id
        ) p ON p.fdc_id = b.fdc_id
        WHERE COALESCE(NULLIF(n.name,''), NULLIF(b.short_desc,'')) IS NOT NULL
        ORDER BY b.fdc_id ASC""")

    count = con.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    meta = {
        "format_version": "1",
        "source": "usda-branded",
        "license": "CC0-1.0",
        "attribution": ATTRIBUTION,
        "built_at": datetime.date.today().isoformat(),
        "product_count": str(count),
        "source_release": source_release,
    }
    con.executemany("INSERT INTO meta VALUES (?,?)", meta.items())

    for stage in ("stage_branded", "stage_name", "stage_nutr"):
        con.execute(f"DROP TABLE {stage}")
    con.commit()
    con.execute("VACUUM")
    con.close()
    print(f"  {count:,} products → {out_path}", file=sys.stderr)
    return out_path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("csv_dir")
    ap.add_argument("out")
    ap.add_argument("--release", required=True,
                    help="upstream release date, e.g. 2025-12-18")
    args = ap.parse_args()
    build_slice(args.csv_dir, args.out, source_release=args.release)


if __name__ == "__main__":
    main()
