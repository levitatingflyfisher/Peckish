# ADR-0008: Target roles + the round-out-your-day engine

**Status:** Accepted (v0.4.0)

## Context

v0.4 finally gave targets a UI (the table had shipped in v0.1 as schema
insurance with no editor at all), and with targets came the request that
motivated them: *"input a rough daily goal of kcal/macros … maybe some
common food suggestions based on regular things eaten that would fill me
up to that goal."*

The design conversation walked through four candidate scorers, and the
trail is worth keeping because each rejection sharpened the requirement:

1. **Weighted vector distance** between a candidate combo's end-of-day
   totals and the targets. Sound, but symmetric: it cannot express
   "prioritize protein", because…
2. **Cosine similarity** (rank by composition match) is scale-invariant
   ratio-matching: a 40-kcal food with a perfect ratio outranks the combo
   that actually closes a 600-kcal day. As a pre-filter it's worse — two
   individually-wrong foods can sum to exactly the right direction, and
   direction-filtering singles discards those complementary pairs.
3. **Magnitude gate + cosine rank** (cover ≥70% of the remaining kcal,
   then rank survivors by composition) is respectable and explainable —
   but still symmetric per axis, and…
4. "Prioritize protein" turned out to mean something *asymmetric*:
   **protein is a floor**. Only falling short matters; past it, free.
   No symmetric metric can say that.

## Decision

**Each macro target carries a role**, stored per column (schema v4,
null = axis default, resolved in the domain):

- `about` — land near it; both directions penalized.
- `atLeast` — a floor; only shortfall penalized. **Protein's default.**
- `under` — a cap; only overage penalized.

Defaults do the setup work: the minimal configuration is typing calories
and protein ("target calories, protein is a floor") with zero role taps.

**The engine** (`suggestion_engine.dart`, pure Dart, no db/clock):
exhaustive search over multisets of ≤3 regulars (multiplicity makes
"3 × Egg" natural), scoring end-of-day totals by summed squared relative
misses under each axis's role. This one mechanism subsumes every
alternative above: plain distance is "all axes about", the magnitude
gate falls out of the kcal axis, and composition-fit emerges without a
single ratio being computed. Familiarity (useCount) breaks ties, the
surfaced ideas must each lead with a different food, and the result is
deterministic — same plate, same advice.

**Statuses are part of the contract:** `complete` (say a finished day is
finished, once, warmly), `quiet` (nothing helps — e.g. already over an
about-target — so say *nothing*; advisory means no scolding), `ideas`.

**The card** logs a whole combo in one tap through the single write
path, dismisses for exactly one day, and has a master switch in
Settings (default on). The switch exists for trust, not performance —
the search is ~5,500 four-number sums, microseconds on any phone.

Targets (roles included) ride backups and plain exports as additive
keys; wire schemaVersion stays 1. They **never sync** — the plate is
yours (ADR-0006).

## Alternatives rejected

- The three scorers above, for the reasons above.
- **LLM-generated suggestions**: the AI rung stays a parser, never a
  planner. Deterministic arithmetic over the user's own habits is
  explainable, offline, and free.
- **Adaptive targets**: still out (ADR-0004). Roles change what a number
  *means*, never the number itself.

## Consequences

- A future axis (fiber, sodium) is a column + an entry in
  `DailyTargets.axes`; the engine and card need no changes.
- The scorer's tolerances (`SuggestionEngine.tolerance` = 5%) define
  "met"; the totals card and the engine must keep sharing that meaning
  through `_satisfied`.
- Suggestion quality is bounded by regulars quality — a household that
  never logs gets `quiet`, which is the honest answer.
