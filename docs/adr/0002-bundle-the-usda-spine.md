# ADR-0002 — Bundle a CC0 USDA food spine; never bundle Open Food Facts

**Status:** accepted · 2026-07-25

## Context

Adversarially-verified research (2026-07) across the FLOSS tracker field
(FoodYou, Waistline, Energize, OpenNutriTracker, FUD AI) found every app
network-dependent for food lookup — none bundles a database. USDA FoodData
Central is public domain (CC0; citation *requested*, not required). Open Food
Facts is ODbL share-alike, and its API terms push bulk users to data dumps.

## Decision

Bundle a distilled USDA spine (Foundation + SR Legacy + FNDDS survey foods:
13,652 foods, 36,669 household portions, 2.4MB JSON / ~520KB compressed) as
an asset, imported into the app database on first boot, version-stamped and
wholesale-replaced on bump. **Never bundle OFF data**: ODbL share-alike would
entangle the portfolio's licensing options for zero offline gain. The live
OFF API remains available later for barcode scans only ("1 API call = 1 real
scan" is the compliant shape).

## Consequences

- Search, logging, planning, and recipe math work offline, forever — the
  differentiator no surveyed competitor ships.
- The spine is reference data: it survives `eraseUserData()`, stays out of
  backups, and refreshes via `tool/usda/` (FNDDS uses legacy nutrient
  NUMBERS where Foundation/SR use FDC ids — the build script handles both).
- Branded/barcode foods are deliberately absent (428MB zipped source);
  custom foods + the future OFF per-scan lookup cover packaged goods.
