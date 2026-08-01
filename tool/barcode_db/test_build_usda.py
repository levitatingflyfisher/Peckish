"""Fixture tests for the USDA Branded slice builder (ADR-0010).

Run: python3 -m unittest tool.barcode_db.test_build_usda  (from repo root)
  or python3 -m unittest test_build_usda                  (from this dir)
"""

import csv
import os
import sqlite3
import tempfile
import unittest

from build_usda import build_slice, normalize_barcode


def _write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        w.writerow(header)
        w.writerows(rows)


BRANDED_HEADER = [
    "fdc_id", "brand_owner", "brand_name", "subbrand_name", "gtin_upc",
    "ingredients", "not_a_significant_source_of", "serving_size",
    "serving_size_unit", "household_serving_fulltext", "branded_food_category",
    "data_source", "package_weight", "modified_date", "available_date",
    "market_country", "discontinued_date", "preparation_state_code",
    "trade_channel", "short_description", "material_code",
]
FOOD_HEADER = [
    "fdc_id", "data_type", "description", "food_category_id",
    "publication_date", "market_country", "trade_channel", "microbe_data",
]
NUTRIENT_HEADER = [
    "id", "fdc_id", "nutrient_id", "amount", "data_points", "derivation_id",
    "min", "max", "median", "footnote", "min_year_acquired",
]


def _branded(fdc_id, gtin, brand_owner="Acme", brand_name="", serving="30.0",
             unit="g", household="2 bars (30 g)", country="United States"):
    return [fdc_id, brand_owner, brand_name, "", gtin, "", "", serving, unit,
            household, "Snacks", "LI", "", "2024-01-01", "2024-02-01",
            country, "", "", "", "", ""]


def _food(fdc_id, description):
    return [fdc_id, "branded_food", description, "", "2024-02-01",
            "United States", "", ""]


def _nutr(row_id, fdc_id, nutrient_id, amount):
    return [row_id, fdc_id, nutrient_id, amount, "", "", "", "", "", "", ""]


class NormalizeTest(unittest.TestCase):
    def test_strips_leading_zeros(self):
        self.assertEqual(normalize_barcode("00027000612323"), "27000612323")

    def test_non_digits_dropped(self):
        self.assertEqual(normalize_barcode(" 0004-9000 "), "49000")

    def test_all_zeros_collapse_to_single_zero(self):
        self.assertEqual(normalize_barcode("0000"), "0")

    def test_empty_is_none(self):
        self.assertIsNone(normalize_barcode(""))
        self.assertIsNone(normalize_barcode("abc"))


class BuildSliceTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.src = self.dir.name
        self.out = os.path.join(self.src, "out.sqlite")

    def tearDown(self):
        self.dir.cleanup()

    def _build(self, branded, foods, nutrients):
        _write_csv(os.path.join(self.src, "branded_food.csv"),
                   BRANDED_HEADER, branded)
        _write_csv(os.path.join(self.src, "food.csv"), FOOD_HEADER, foods)
        _write_csv(os.path.join(self.src, "food_nutrient.csv"),
                   NUTRIENT_HEADER, nutrients)
        return build_slice(self.src, self.out, source_release="2025-12-18")

    def _rows(self):
        con = sqlite3.connect(self.out)
        rows = {r[0]: r for r in con.execute(
            "SELECT barcode,name,brand,kcal,protein_g,carb_g,fat_g,"
            "serving_g,serving_label FROM products")}
        meta = dict(con.execute("SELECT key,value FROM meta"))
        con.close()
        return rows, meta

    def test_happy_row_maps_every_field(self):
        self._build(
            [_branded("11", "00012345678905")],
            [_food("11", "Chocolate Bar")],
            [_nutr(1, "11", "1008", "500"), _nutr(2, "11", "1003", "7.5"),
             _nutr(3, "11", "1005", "55"), _nutr(4, "11", "1004", "30")],
        )
        rows, meta = self._rows()
        self.assertEqual(
            rows["12345678905"],
            ("12345678905", "Chocolate Bar", "Acme", 500.0, 7.5, 55.0, 30.0,
             30.0, "2 bars (30 g)"))
        self.assertEqual(meta["source"], "usda-branded")
        self.assertEqual(meta["license"], "CC0-1.0")
        self.assertEqual(meta["product_count"], "1")
        self.assertEqual(meta["source_release"], "2025-12-18")
        self.assertEqual(meta["format_version"], "1")
        self.assertIn("U.S. Department of Agriculture", meta["attribution"])

    def test_unknown_macros_stay_null_never_zero(self):
        self._build(
            [_branded("11", "00012345678905")],
            [_food("11", "Mystery Snack")],
            [_nutr(1, "11", "1008", "100")],  # only energy known
        )
        rows, _ = self._rows()
        _, _, _, kcal, protein, carb, fat, _, _ = rows["12345678905"]
        self.assertEqual(kcal, 100.0)
        self.assertIsNone(protein)
        self.assertIsNone(carb)
        self.assertIsNone(fat)

    def test_energy_prefers_1008_over_atwater(self):
        self._build(
            [_branded("11", "00012345678905")],
            [_food("11", "Bar")],
            [_nutr(1, "11", "2047", "480"), _nutr(2, "11", "1008", "500"),
             _nutr(3, "11", "2048", "490")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows["12345678905"][3], 500.0)

    def test_atwater_used_when_1008_missing(self):
        self._build(
            [_branded("11", "00012345678905")],
            [_food("11", "Bar")],
            [_nutr(1, "11", "2047", "480")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows["12345678905"][3], 480.0)

    def test_same_barcode_latest_fdc_id_wins(self):
        self._build(
            [_branded("11", "00012345678905"),
             _branded("99", "0012345678905", brand_owner="Newer Acme")],
            [_food("11", "Old Name"), _food("99", "New Name")],
            [_nutr(1, "11", "1008", "100"), _nutr(2, "99", "1008", "200")],
        )
        rows, meta = self._rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows["12345678905"][1], "New Name")
        self.assertEqual(rows["12345678905"][3], 200.0)
        self.assertEqual(meta["product_count"], "1")

    def test_non_us_rows_skipped(self):
        self._build(
            [_branded("11", "00012345678905", country="New Zealand")],
            [_food("11", "Kiwi Bar")],
            [_nutr(1, "11", "1008", "100")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows, {})

    def test_missing_gtin_skipped(self):
        self._build(
            [_branded("11", "")],
            [_food("11", "No Code")],
            [_nutr(1, "11", "1008", "100")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows, {})

    def test_name_falls_back_to_short_description(self):
        branded = _branded("11", "00012345678905")
        branded[19] = "Short Name"  # short_description column
        self._build([branded], [_food("11", "")],
                    [_nutr(1, "11", "1008", "100")])
        rows, _ = self._rows()
        self.assertEqual(rows["12345678905"][1], "Short Name")

    def test_nameless_row_skipped(self):
        self._build([_branded("11", "00012345678905")], [_food("11", "")],
                    [_nutr(1, "11", "1008", "100")])
        rows, _ = self._rows()
        self.assertEqual(rows, {})

    def test_ml_serving_kept_gram_equivalent(self):
        self._build(
            [_branded("11", "00012345678905", serving="240.0", unit="ml",
                      household="1 cup")],
            [_food("11", "Broth")],
            [_nutr(1, "11", "1008", "10")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows["12345678905"][7], 240.0)
        self.assertEqual(rows["12345678905"][8], "1 cup")

    def test_weird_serving_unit_drops_grams_keeps_label(self):
        self._build(
            [_branded("11", "00012345678905", serving="2.0", unit="IU",
                      household="2 things")],
            [_food("11", "Odd")],
            [_nutr(1, "11", "1008", "10")],
        )
        rows, _ = self._rows()
        self.assertIsNone(rows["12345678905"][7])
        self.assertEqual(rows["12345678905"][8], "2 things")

    def test_brand_name_preferred_over_owner(self):
        self._build(
            [_branded("11", "00012345678905", brand_owner="MEGACORP INC",
                      brand_name="Nice Brand")],
            [_food("11", "Bar")],
            [_nutr(1, "11", "1008", "100")],
        )
        rows, _ = self._rows()
        self.assertEqual(rows["12345678905"][2], "Nice Brand")


if __name__ == "__main__":
    unittest.main()
