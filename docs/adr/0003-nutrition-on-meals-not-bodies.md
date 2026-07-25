# ADR-0003 — Nutrition attaches to meals, not bodies

**Status:** accepted · 2026-07-25

## Decision

Peckish is a family app, and its nutrition layer describes the household's
food: what this week's dinners look like, what a recipe carries per serving.
It is deliberately not a surveillance surface for anyone's body. Concretely:

- The plan and recipe surfaces show per-serving/household facts, advisory
  tone, clay-never-red.
- The personal diary is an optional rung — recents, totals, static targets —
  for a person who wants their own numbers. It is per-person by design and
  will stay private-by-default when multi-device sync arrives.
- No streaks, no scores, no coaching copy, no notifications. The app never
  initiates a conversation about food.

## Why

Positive framing is the product: a calm tool a family actually keeps using.
Every commercial competitor monetizes engagement mechanics; refusing them is
both the values call and the differentiation.
