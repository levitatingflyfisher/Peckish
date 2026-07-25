#!/usr/bin/env python3
"""Build Peckish's bundled USDA food spine from FDC bulk CSVs.

Output: usda_foods.json — {"v":1,"foods":[[id,src,name,kcal,p,c,f,fiber,sugar,sodium_mg],...],
                            "portions":[[food_id,label,grams],...]}
All nutrient amounts are per 100 g. Source: USDA FoodData Central (CC0).
"""
import csv, json, os, sys
from collections import defaultdict

BASE = os.path.dirname(os.path.abspath(__file__))
SETS = [
    ("foundation", "FoodData_Central_foundation_food_csv_2026-04-30/FoodData_Central_foundation_food_csv_2026-04-30", "foundation_food"),
    ("sr", "FoodData_Central_sr_legacy_food_csv_2018-04/FoodData_Central_sr_legacy_food_csv_2018-04", "sr_legacy_food"),
    ("survey", "FoodData_Central_survey_food_csv_2024-10-31/FoodData_Central_survey_food_csv_2024-10-31", "survey_fndds_food"),
]

# The food_nutrient.csv `nutrient_id` column carries FDC ids in the
# foundation/SR sets but LEGACY nutrient numbers in the FNDDS survey set —
# accept both spellings of each nutrient. kcal falls back 1008/208 → Atwater.
KCAL_IDS = [1008, 208, 2047, 2048]
SLOT_IDS = {"p": (1003, 203), "c": (1005, 205), "f": (1004, 204),
            "fiber": (1079, 291), "sugar": (2000, 269), "na": (1093, 307)}

def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        yield from csv.DictReader(fh)

foods, portions = [], []
counts = defaultdict(int)

for src, rel, dtype in SETS:
    d = os.path.join(BASE, rel)
    # 1. fdc_id → name for real foods only
    names = {}
    for row in read_csv(os.path.join(d, "food.csv")):
        if row["data_type"] == dtype:
            desc = row["description"].strip()
            if desc:
                names[int(row["fdc_id"])] = desc
    # 2. nutrients
    nut = defaultdict(dict)  # fdc_id → {nutrient_id: amount}
    for row in read_csv(os.path.join(d, "food_nutrient.csv")):
        fid = int(row["fdc_id"])
        if fid not in names:
            continue
        try:
            nid = int(float(row["nutrient_id"]))
            amt = float(row["amount"])
        except (ValueError, KeyError):
            continue
        # keep the FIRST value seen per nutrient (foundation has dupes across
        # derivations; first row is the aggregate)
        nut[fid].setdefault(nid, amt)
    # 3. measure units
    units = {}
    mu = os.path.join(d, "measure_unit.csv")
    if os.path.exists(mu):
        for row in read_csv(mu):
            units[row["id"]] = row["name"]
    # 4. portions
    per_food_portions = defaultdict(list)
    fp = os.path.join(d, "food_portion.csv")
    if os.path.exists(fp):
        for row in read_csv(fp):
            fid_raw = row.get("fdc_id")
            if not fid_raw:
                continue
            fid = int(fid_raw)
            if fid not in names:
                continue
            try:
                grams = float(row["gram_weight"])
            except (ValueError, KeyError):
                continue
            if grams <= 0:
                continue
            desc = (row.get("portion_description") or "").strip()
            if not desc or desc == "Quantity not specified":
                amount = (row.get("amount") or "").strip()
                unit = units.get(row.get("measure_unit_id", ""), "")
                if unit == "undetermined":
                    unit = ""
                modifier = (row.get("modifier") or "").strip()
                bits = " ".join(x for x in [amount, unit] if x)
                if modifier:
                    # No real unit (SR stores "undetermined" + the unit inside
                    # the modifier, e.g. "cup slices"): join with a space, not
                    # a comma — "1 cup slices", never "1, cup slices".
                    bits = f"{bits}, {modifier}" if unit else (
                        f"{bits} {modifier}" if bits else modifier)
                desc = bits.strip()
            if not desc:
                continue
            # normalize "1.0" → "1"
            desc = desc.replace(".0 ", " ") if desc.startswith(("0.", "1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9.")) else desc
            per_food_portions[fid].append((desc, round(grams, 2)))
    # 5. emit
    for fid, name in sorted(names.items()):
        n = nut.get(fid, {})
        kcal = next((n[k] for k in KCAL_IDS if k in n), None)
        row = [fid, src, name,
               None if kcal is None else round(kcal, 1)]
        for slot in ("p", "c", "f", "fiber", "sugar", "na"):
            v = next((n[k] for k in SLOT_IDS[slot] if k in n), None)
            row.append(None if v is None else round(v, 2))
        # skip foods with no energy AND no macros at all (lab-only rows)
        if row[3] is None and row[4] is None and row[5] is None and row[6] is None:
            counts[f"{src}_skipped_no_data"] += 1
            continue
        foods.append(row)
        counts[src] += 1
        seen = set()
        for desc, grams in per_food_portions.get(fid, []):
            key = (desc.lower(), grams)
            if key in seen:
                continue
            seen.add(key)
            portions.append([fid, desc, grams])

out = {"v": 1, "foods": foods, "portions": portions}
path = os.path.join(BASE, "usda_foods.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(out, fh, separators=(",", ":"), ensure_ascii=False)

print(dict(counts))
print("foods:", len(foods), "portions:", len(portions))
print("bytes:", os.path.getsize(path))

# sanity spot-checks
by_name = {(f[2].lower(), f[1]): f for f in foods}
def check(name, src, kcal_lo, kcal_hi):
    f = by_name.get((name.lower(), src))
    if not f:
        print("MISSING:", name, src); return
    ok = f[3] is not None and kcal_lo <= f[3] <= kcal_hi
    print(("OK  " if ok else "BAD "), f[2][:40], "| kcal", f[3], "p", f[4], "c", f[5], "f", f[6])

check("Butter, salted", "sr", 700, 730)
check("Chicken, broilers or fryers, breast, meat only, raw", "sr", 100, 130)
check("Apples, raw, with skin", "sr", 45, 60)
