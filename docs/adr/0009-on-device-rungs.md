# ADR-0009: The on-device rungs — a plate labeler and a pocket parser

**Status:** Accepted (v0.5.0)

## Context

The AI guesstimate (v0.2) had two rungs: BYOK Claude and a self-hosted
OpenAI-compatible server. Both are real opt-ins, but both need something
beyond the phone. The fleet already solved on-device inference twice —
StillLife's Intelligence rungs (CV) and Reckon's flutter_gemma spine
(text) — so Peckish ports the proven halves of each, as strictly
optional tiers.

## Decision

**Rung: Snap your plate** (StillLife rung-1 pattern). ML Kit's bundled
image labeler (in Play Services — zero download) labels a photo; labels
become draft lines through the BUNDLED USDA spine at real household
portions. The StillLife laws travel: a label is hand-mapped to a food
search or SKIPPED (generic scene words deliberately unmapped), the
confidence shown is the classifier's real number, a spine miss yields
nothing, and drafts cap at four lines. No LLM, no network, no opt-in
needed — the classifier and the spine are both already on the phone.
Confirm-before-commit is unchanged.

**Rung: On this phone** (the Reckon spine). `AiBackend.onDevice` runs a
downloaded Qwen `.task` through flutter_gemma — same canonical prompt,
same tolerant `MealGuess.parse`, not one word leaves the device. The
ported trust laws are tests: litert-community only, ungated only, no
litert-lm ("TFL3") URLs, and the DEFAULT is the 0.5B — parsing "two
eggs and toast" is not a 1.6 GB job. The downloader is Reckon's proven
resumable service (Range/.part/416/ignored-Range, atomic rename IS the
completeness proof). One resident model, fresh chat per guess, gate on
is-downloaded before any native loading.

**Platform honesty.** Both rungs are Android-only, behind conditional-
export trios (io default, web via `dart.library.js_interop`) — the web
build never compiles a plugin it can't use, and unsupported platforms
simply don't render the affordances. Android carries the Reckon gradle
lessons: minSdk 24, largeHeap, and the verified jniLibs exclude list
(text inference keeps two native families, not seven).

## Descoped, deliberately

- **StillLife's SmolVLM rung** (GB-scale vision LLM, committed arm64
  AAR): poor value-per-GB for a food diary whose canonical input is a
  sentence. The plate labeler covers photos at zero download; the text
  brain covers language at 550 MB.
- **Gemini Nano (AICore)**: a fourth brain for the same guess box —
  revisit when the AICore surface stabilizes; the seam (LocalBrain) is
  one file.
- Photo capture uses the system camera/picker via image_picker — no new
  manifest permissions of Peckish's own.

## Consequences

- The APK grows by the MediaPipe/ML Kit runtime even with the exclude
  list — a deliberate, budgeted cost recorded in budgets.json.
- The on-device paths are unit-tested through fakes (the Reckon
  fake-session harness drives the real InferenceChat machinery) but not
  yet device-verified — same posture StillLife ships under, and the
  first phone test is the referee.
- A future gated model would need the HF-token machinery back; the
  catalog test currently forbids it on purpose.
