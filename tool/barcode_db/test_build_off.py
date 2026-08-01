"""Fixture tests for the Open Food Facts slice builder (ADR-0010).

Builds a tiny parquet with duckdb mirroring the real food.parquet's nested
shapes (minimal struct fields — duckdb lambdas only touch what they name),
then asserts the sqlite output. Run: python3 -m unittest test_build_off
"""

import os
import sqlite3
import tempfile
import unittest

import duckdb

from build_off import build_slice

US = "en:united-states"


def _fixture_parquet(path, rows):
    """rows: list of dicts with keys code, names [(lang,text)], brands,
    nutrs [(name, per100g)], serving_size, serving_quantity, countries,
    obsolete."""
    con = duckdb.connect()
    selects = []
    for r in rows:
        names = ", ".join(
            "{'lang': '%s', 'text': '%s'}" % (lang, text)
            for lang, text in r.get("names", []))
        nutrs = ", ".join(
            "{'name': '%s', '100g': %s}" % (n, "NULL" if v is None else v)
            for n, v in r.get("nutrs", []))
        countries = ", ".join("'%s'" % c for c in r.get("countries", [US]))
        selects.append(f"""SELECT
            '{r["code"]}' AS code,
            [{names}]::STRUCT(lang VARCHAR, "text" VARCHAR)[] AS product_name,
            {'NULL' if r.get("brands") is None else "'%s'" % r["brands"]} AS brands,
            [{nutrs}]::STRUCT("name" VARCHAR, "100g" FLOAT)[] AS nutriments,
            {'NULL' if r.get("serving_size") is None else "'%s'" % r["serving_size"]} AS serving_size,
            {'NULL' if r.get("serving_quantity") is None else "'%s'" % r["serving_quantity"]} AS serving_quantity,
            [{countries}]::VARCHAR[] AS countries_tags,
            {str(r.get("obsolete", False)).upper()} AS obsolete""")
    con.execute("COPY (%s) TO '%s' (FORMAT PARQUET)" % (" UNION ALL ".join(selects), path))
    con.close()


class BuildOffTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.parquet = os.path.join(self.dir.name, "food.parquet")
        self.out = os.path.join(self.dir.name, "out.sqlite")

    def tearDown(self):
        self.dir.cleanup()

    def _build(self, rows):
        _fixture_parquet(self.parquet, rows)
        build_slice(self.parquet, self.out, country_tag=US)
        con = sqlite3.connect(self.out)
        got = {r[0]: r for r in con.execute(
            "SELECT barcode,name,brand,kcal,protein_g,carb_g,fat_g,"
            "serving_g,serving_label FROM products")}
        meta = dict(con.execute("SELECT key,value FROM meta"))
        con.close()
        return got, meta

    def test_happy_row_maps_every_field(self):
        rows, meta = self._build([{
            "code": "0012345678905",
            "names": [("en", "Peanut Butter")],
            "brands": "Goober",
            "nutrs": [("energy-kcal", 588), ("proteins", 25),
                      ("carbohydrates", 20), ("fat", 50)],
            "serving_size": "2 tbsp (32 g)", "serving_quantity": "32",
        }])
        self.assertEqual(
            rows["12345678905"],
            ("12345678905", "Peanut Butter", "Goober", 588.0, 25.0, 20.0,
             50.0, 32.0, "2 tbsp (32 g)"))
        self.assertEqual(meta["source"], "off")
        self.assertEqual(meta["license"], "ODbL-1.0")
        self.assertIn("Open Food Facts", meta["attribution"])
        self.assertIn("opendatacommons.org/licenses/odbl", meta["license_url"])
        self.assertEqual(meta["product_count"], "1")

    def test_non_us_rows_skipped(self):
        rows, _ = self._build([{
            "code": "40084015", "names": [("en", "Haribo")],
            "nutrs": [("energy-kcal", 343)], "countries": ["en:germany"],
        }])
        self.assertEqual(rows, {})

    def test_obsolete_rows_skipped(self):
        rows, _ = self._build([{
            "code": "40084015", "names": [("en", "Gone")],
            "nutrs": [("energy-kcal", 343)], "obsolete": True,
        }])
        self.assertEqual(rows, {})

    def test_name_prefers_en_then_main_then_first(self):
        rows, _ = self._build([
            {"code": "1000000000017",
             "names": [("fr", "Beurre"), ("en", "Butter"), ("main", "Main")],
             "nutrs": [("energy-kcal", 717)]},
            {"code": "2000000000012",
             "names": [("fr", "Confiture"), ("main", "Jam")],
             "nutrs": [("energy-kcal", 250)]},
            {"code": "3000000000017", "names": [("de", "Brot")],
             "nutrs": [("energy-kcal", 250)]},
        ])
        self.assertEqual(rows["1000000000017"][1], "Butter")
        self.assertEqual(rows["2000000000012"][1], "Jam")
        self.assertEqual(rows["3000000000017"][1], "Brot")

    def test_kj_only_label_converts_to_kcal(self):
        rows, _ = self._build([{
            "code": "1000000000017", "names": [("en", "EU Thing")],
            "nutrs": [("energy", 1000)],
        }])
        self.assertAlmostEqual(rows["1000000000017"][3], 1000 / 4.184, places=2)

    def test_unknown_macros_stay_null(self):
        rows, _ = self._build([{
            "code": "1000000000017", "names": [("en", "Sparse")],
            "nutrs": [("energy-kcal", 100)],
        }])
        _, _, _, kcal, protein, carb, fat, serving_g, _ = rows["1000000000017"]
        self.assertEqual(kcal, 100.0)
        self.assertIsNone(protein)
        self.assertIsNone(carb)
        self.assertIsNone(fat)
        self.assertIsNone(serving_g)

    def test_nameless_rows_skipped(self):
        rows, _ = self._build([{
            "code": "1000000000017", "names": [],
            "nutrs": [("energy-kcal", 100)],
        }])
        self.assertEqual(rows, {})

    def test_barcodes_normalized_leading_zeros(self):
        rows, _ = self._build([{
            "code": "0049000000443", "names": [("en", "Cola")],
            "nutrs": [("energy-kcal", 42)],
        }])
        self.assertIn("49000000443", rows)

    def test_unparseable_serving_quantity_dropped(self):
        rows, _ = self._build([{
            "code": "1000000000017", "names": [("en", "Odd")],
            "nutrs": [("energy-kcal", 100)],
            "serving_size": "one handful", "serving_quantity": "approx 30",
        }])
        self.assertIsNone(rows["1000000000017"][7])
        self.assertEqual(rows["1000000000017"][8], "one handful")


if __name__ == "__main__":
    unittest.main()
