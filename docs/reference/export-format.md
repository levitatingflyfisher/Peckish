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
  "targets":      { "kcal?", "proteinG?", "carbG?", "fatG?" }
}
```

- Macro objects omit unknown slots entirely — absent means unknown, never 0.
- `food` refs: `{"kind":"usda","usdaFdcId":…}` / `{"kind":"custom","customFoodId":…}` /
  `{"kind":"quick"}`.
- Absent sections restore as empty; unknown keys are ignored (additive keys
  never bump `schemaVersion`).
- The encrypted `.ohbk` payload is this same document, wrapped by the
  sanctuary envelope (AEAD context `peckish-backup/v1`).
