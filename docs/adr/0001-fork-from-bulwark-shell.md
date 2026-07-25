# ADR-0001 — Fork the app shell from Bulwark

**Status:** accepted · 2026-07-25

Peckish scaffolds from Bulwark (itself Furrow's descendant) — the newest
fleet conventions in one place: riverpod codegen, drift + drift_flutter with
the web WASM wiring, go_router, bundled Lora/Nunito, sanctuary encrypted
backup, oh_fleet_conformance, and the CI/release workflows. All Bulwark
domain features were stripped before the first commit; identity
(com.openhearth.peckish, the jam/oat/butter palette) was set from commit 1 —
the fleet's applicationId lesson, applied from birth.
