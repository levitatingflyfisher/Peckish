# ADR-0004 — Static targets; no adaptive-TDEE loop

**Status:** accepted · 2026-07-25

## Context

MacroFactor's differentiator is an adaptive expenditure loop (intake log +
weight trend → TDEE estimate). Its accuracy claim (median error 135 vs 335
kcal) is vendor-self-published, and — decisively — the principal user
explicitly declined the loop: static numbers, changed by hand.

## Decision

Targets are four nullable numbers in a single row. No loop code ships. The
schema deliberately keeps the two things a future opt-in loop would need —
per-entry timestamps and the static target fields — so the loop stays a
~50-line addition, not a migration. Nothing else is pre-built.

## Consequence

The guesstimate-first logging philosophy still holds (consistency beats
precision for repeated meals); the app just refuses to editorialize about
expenditure.
