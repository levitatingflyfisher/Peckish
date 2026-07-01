# ADR-0005 — v0.1 is single-device; sync is CRDT-over-blind-relay later

**Status:** accepted · 2026-07-25

## Context

Verified research: NO shipped app achieves serverless account-free
multi-device family sync — every architecture needs some node. The three real
no-vendor-cloud patterns are a self-hosted LAN server (openCook), file-sync
delegation (woefe/Syncthing — no merge logic, cautionary), and Dart-native
CRDT over an accountless websocket relay (tudo's sqlite_crdt + crdt_sync).

## Decision

Ship v0.1 single-device. When shared plan/groceries earn their build, the
path is the tudo pattern — full local replica per device, delta changesets
over a blind encrypted relay (the fleet's existing relay philosophy;
StillLife's encrypted LAN sync is the in-fleet sibling) — never a
server-with-accounts, never a BaaS.

## Consequence

The `.ohbk` backup is the household's data hop in the meantime, and nothing
in the schema assumes a single writer forever (string PKs everywhere).
