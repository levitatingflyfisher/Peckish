# Regenerating the bundled USDA food spine

`assets/food/usda_foods.json` is built from three USDA FoodData Central bulk
CSV releases (public domain, CC0 — https://fdc.nal.usda.gov/):

- Foundation Foods (lab-analyzed whole foods)
- SR Legacy (the classic generic-food reference, final release 2018-04)
- FNDDS / Survey Foods (as-consumed mixed dishes — the "Egg burrito" tier)

To refresh: download the current `*_csv_*.zip` for each from
https://fdc.nal.usda.gov/download-datasets, unzip them next to
`build_spine.py`, update the `SETS` paths, and run `python3 build_spine.py`.
Copy the resulting `usda_foods.json` over `assets/food/usda_foods.json`.

Format: `{"v":1,"foods":[[fdcId,src,name,kcal,protein,carb,fat,fiber,sugar,
sodiumMg],...],"portions":[[fdcId,label,grams],...]}` — all per 100 g.
Gotcha the script already handles: FNDDS's food_nutrient.csv uses LEGACY
nutrient numbers (208/203/204/205/269/291/307) where foundation/SR use FDC
ids (1008/1003/...); both are accepted per slot.
