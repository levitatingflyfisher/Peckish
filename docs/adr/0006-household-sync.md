# ADR-0006: Household sync — encrypted LAN, LWW, and the shared/private split

Date: 2026-07-27 · Status: accepted · Supersedes the "single-device-first"
posture of [ADR-0005](0005-single-device-first.md) (which planned exactly
this step).

## Decision

v0.2 ships device-to-device sync over the household's own Wi-Fi, modeled
closely on StillLife's shipped LAN sync (the in-fleet sibling), with these
choices:

**The kitchen is shared, the plate is yours.** Five tables sync — custom
foods, saved meals, recipes, plan entries, grocery items. Diary entries and
targets NEVER enter a changeset (a test greps the payload to keep this
true). One plan and one list per household; each person's diary stays on
their device.

**Wire.** An embedded shelf server on port 8421 with three endpoints:
`/sync/status` (cleartext probe: node id, clock, protocol version, a
single-use replay challenge), `/sync/export` and `/sync/import` (binary
AEAD frames — `nonce(12) ‖ ciphertext ‖ mac(16)` — ChaCha20-Poly1305 under
a key HKDF-derived from the household code, domain `peckish.lan.v1`). AAD
binds every frame to endpoint + protocol version (+ challenge on import),
so frames cannot be replayed across endpoints or versions. Pairing IS the
code: no accounts, no server anywhere.

**Merge.** Per-row last-write-wins by Hybrid Logical Clock. Every write to
a synced table stamps `hlc` + `nodeId`; deletes are tombstones
(`isDeleted`), hidden from every read and carried by sync so deletions
travel. A remote row applies only when no local row exists or its stamp
compares strictly greater — a stale peer can neither clobber a newer edit
nor resurrect a newer tombstone (StillLife's sev-8 lesson, baked in from
day one and pinned by tests). Children (meal items, recipe ingredients)
travel with their parent as one unit at the parent's granularity.

**Grocery convergence.** Plan-derived grocery rows use DETERMINISTIC ids
(uuid5 of the normalized ingredient line), so two devices regenerating the
same plan mint the same rows and LWW converges instead of duplicating.
This also made regeneration idempotent locally.

**Two version axes.** `SyncCodec.protocolVersion` (crypto wire, negotiated
in cleartext, fail-closed on old peers) and
`SyncChangeset.payloadSchemaVersion` (row semantics; a payload from a newer
app version is refused before any write).

## Honest scorecard

- **Not forward secrecy.** The frame key is a static HKDF(household code);
  rotating the code rotates the key. Same posture as StillLife, stated
  plainly.
- **`/sync/export` is unauthenticated-triggerable.** Any LAN host can make
  the device produce ciphertext and tick its clock. Confidentiality holds;
  the cost is benign. Documented asymmetry.
- **Restore resurrects deliberately.** Backups carry live data without
  sync metadata; restoring an old backup re-creates rows with fresh stamps
  that then win LWW. Restore is an explicit act; this is its meaning.
- **Tombstones are kept forever** (v0.2). Grocery/plan tombstone volume is
  tiny; a compaction pass is future work.
- **mDNS discovery deferred.** Manual IP entry ships first — it always
  works; discovery is sugar for later.
- **Native-only.** A browser cannot bind a server; the web build shows a
  calm "not available" state.
