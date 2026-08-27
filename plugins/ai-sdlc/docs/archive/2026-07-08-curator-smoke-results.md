# Memory Curator — Smoke Test Results

**Date:** 2026-07-08
**Subject:** `sdlc-curator` agent (see `docs/specs/2026-07-08-ai-sdlc-memory-curator-design.md`)
**Method:** Planted fixture corpus under `/tmp/curator-smoke/` (3 always-loaded role files, 2 on-demand recipe files, 1-event journal), each fixture engineered to trigger exactly one expected behavior. The agent was spawned as a general-purpose `Agent()` pointing at its real role file — the same spawn shape the orchestrator uses.

## Fixtures → tests

| Fixture | Plants |
|---|---|
| `always/roleA.md` | git-C rule (dup w/ roleB), unique Playwright principle, `squash-merge` directive |
| `always/roleB.md` | git-C rule (dup w/ roleA), `never squash-merge` directive (contradiction) |
| `always/roleC.md` | dead ref `sdlc-nonexistent.md` (stale) + valid ref `roleA.md` |
| `ondemand/recipes-old.md` | rotted `--foo` recipe, NOT in journal → clean Tier-A delete |
| `ondemand/recipes-new.md` | rotted `--bar` recipe that the journal shows was recently ADDED → anti-thrash |
| `journal.jsonl` | one approved lesson (`evt_seed_1`) that added the `--bar` recipe |

## Results

| # | Test | Expected | Outcome |
|---|---|---|---|
| T1 | Duplicate detection | consolidate, Tier B, real per-spawn token win (separate files) | ✅ PASS |
| T2 | Contradiction resolution | resolve-contradiction, both sides shown, no silent pick | ✅ PASS |
| T3 | Stale reference | flag `sdlc-nonexistent.md`; spare the valid `roleA.md` ref | ✅ PASS (correctly spared valid ref) |
| T4 | Recipe deletion (Tier A) | delete rotted `--foo`, anti-thrash passes | ✅ PASS |
| T5 | Never-delete-principle invariant | roleA's unique Playwright rule never proposed for deletion | ✅ PASS |
| T6 | Leverage ranking + drop cap | always-loaded ranked above on-demand; drop line present | ⚠️ PARTIAL — ordering correct; the >15 cap was not stress-tested (only 5 candidates existed) |
| T7 | Toggle OFF → silence | return `nothing-to-curate`, read nothing | ❌→✅ FIXED (see below) |
| T8 | Anti-thrash | flag `--bar` as `recently-added — confirm intent`, archive not delete, cite the journal event | ✅ PASS (cited `evt_seed_1`) |
| T9 | Anti-bloat | bounded return; corpus stays in sub-agent | ✅ PASS (~38k tokens spent in-agent, ~1k returned) |

## T7 failure and fix

**Initial run FAILED:** with `Self-Learning: OFF`, the agent ran the full corpus scan and produced a proposal anyway — the belt-and-suspenders toggle gate was skipped. Root cause: the gate sat as step 2 of `## Process`, below "Read your role definition," and lost to the strong spawn-prompt framing "execute your Process against the corpus."

**Fix:** hoisted the gate to a `⛔ STOP` block in the agent intro (before `## Process` begins) that explicitly overrides the "execute against the corpus" instruction, and made it Process step 1. Note: in production the *command layer* hard-gates first (refuses to spawn when OFF), so this is the secondary net — but a net that doesn't hold isn't one.

**Re-run PASSED:** 1 tool use (role read only), 6s, immediate `## Verdict: nothing-to-curate` — no corpus read, no journal read.

## Remaining

- **T6 cap:** not stress-tested. Needs a >15-candidate corpus to confirm the top-N cut + "Dropped: N" accounting under real pressure. Low risk (the drop line rendered correctly with 0 drops).
- **Command-path E2E:** these tests exercise the *agent*. The `/sdlc lessons curate` command flow (glob → spawn → surface → per-item apply → journal) was driven manually in the first real-corpus run, not yet as one automated path.
