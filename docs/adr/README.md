# Architecture Decision Records

| # | Decision |
|---|---|
| [0001](0001-fork-from-bulwark-shell.md) | Fork the app shell from Bulwark |
| [0002](0002-bundle-the-usda-spine.md) | Bundle a CC0 USDA food spine; never bundle Open Food Facts |
| [0003](0003-nutrition-on-meals-not-bodies.md) | Nutrition attaches to meals, not bodies |
| [0004](0004-static-targets-no-adaptive-loop.md) | Static targets; no adaptive-TDEE loop |
| [0005](0005-single-device-first.md) | v0.1 is single-device; sync is CRDT-over-blind-relay later |
| [0006](0006-household-sync.md) | Household LAN sync: the kitchen is shared, the plate is yours |
| [0007](0007-persistent-regulars.md) | Regulars are a persistent record, not a diary echo |
| [0008](0008-target-roles-and-suggestions.md) | Targets carry roles (floor/cap/about); suggestions come from asymmetric-penalty search over regulars |
| [0009](0009-on-device-rungs.md) | On-device rungs: ML Kit plate labeler + downloaded Qwen via flutter_gemma, both optional, Android-only |
| [0010](0010-offline-barcode-sovereignty.md) | Offline barcode sovereignty: downloadable USDA/OFF slices, never merged; the network is one explicit tap |
