# Export format

`peckish-export-YYYY-MM-DD.json` — one JSON object:

```jsonc
{
  "app": "peckish",
  "schemaVersion": 1,          // wire version — NOT the drift schema version
  "createdAt": "…ISO-8601…",
  "customFoods":  [ { "id", "name", "servingLabel", "perServing", "createdAt", "archived" } ],
  "diaryEntries": [ { "id", "day", "at", "food", "label", "qty", "unitLabel", "grams?", "macros", "source", "createdAt" } ],
  "savedMeals":   [ { "id", "name", "position", "createdAt", "lastUsedAt?", "archived", "items": [...] } ],
  "recipes":      [ { "id", "title", "servings?", "sourceUrl?", "instructions", "declaredPerServing?", "createdAt", "archived", "ingredients": [...] } ],
  "planEntries":  [ { "id", "day", "slot", "kind", "refId?", "note?" } ],
  "groceryItems": [ { "id", "name", "aisle", "checked", "manual", "sourceRecipeId?", "createdAt" } ],
  "foodUsages":   [ { "food", "label", "qty", "unitLabel", "grams?", "macros", "useCount", "lastUsedAt", "hidden" } ],
  "targets":      { "kcal?", "proteinG?", "carbG?", "fatG?" }
}
```

- Macro objects omit unknown slots entirely — absent means unknown, never 0.
- `food` refs: `{"kind":"usda","usdaFdcId":…}` / `{"kind":"custom","customFoodId":…}` /
  `{"kind":"quick"}`.
- Absent sections restore as empty; unknown keys are ignored (additive keys
  never bump `schemaVersion`).
- `foodUsages` (added in 0.3, additive) is the persistent regulars record.
  Its identity key is re-derived from `food` + `label` on import, never
  stored twice. On restore the diary replay re-derives usage first, then
  these rows overwrite it — counts and `hidden` flags aren't derivable from
  the ledger.
- The encrypted `.ohbk` payload is this same document, wrapped by the
  sanctuary envelope (AEAD context `peckish-backup/v1`).
