# ADR-0007: Regulars are a persistent record, not a diary echo

Status: accepted (v0.3) · Date: 2026-07-28

## Context

Through v0.2 the one-tap rail ("Your regulars") was a query over live diary
rows — the most recent entries, deduped by food identity. Phone testing
surfaced the flaw: delete a day's entries (a mislog, a cleanup) and the
regulars derived from them vanish. The habit record and the ledger were the
same table, so editing one erased the other.

## Decision

A dedicated `food_usages` table, keyed by `FoodRef.identityKey`. Every
diary log — every source: tap, search, quick add, AI, scan, saved meal —
upserts one row: use count, last-used timestamp, and the newest log's
snapshot (qty/unit/grams/macros). Diary deletion never touches it. The rail
and the Foods screen read only this table. "Hide from rail" is a flag on
the row, and any fresh log unhides.

Consequences accepted in the same change (the growth law):

- Schema v3 creates the table and backfills it from the existing diary, so
  the update lands with the rail intact.
- `eraseUserData` wipes it; export/backup carry it as an additive section
  (wire `schemaVersion` stays 1 — old files restore with usage re-derived
  from the diary replay; new files overwrite the replay with exported truth,
  because counts and hidden flags are not derivable from the ledger).
- It never syncs. It derives from the diary, and the diary is the plate —
  ADR-0006's boundary applies transitively.

## Alternatives considered

- **Widen the recents query** (scan more days): still an echo — any full
  deletion of a food's history erases the habit. Rejected.
- **Pin favorites manually**: a second concept ("favorites") beside the
  automatic rail; more UI, and the automatic rail would still be fragile.
  The usage record keeps the rail automatic AND durable, with hide as the
  only manual verb. Rejected.
