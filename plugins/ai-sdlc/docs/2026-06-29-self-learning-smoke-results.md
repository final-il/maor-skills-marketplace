# Self-Learning Hook Capture — Phase D Smoke Verification Results (CSI-641)

**Date:** 2026-06-29
**Epic:** CSI-634 (AI-SDLC self-learning, hook-based capture loop)
**Gate:** QA-distrust verification gate for the whole capture loop. Every
assertion reads the **actual journal file** and inspects it with `jq` — no
agent/QA report is trusted.

**Suite:** `plugins/ai-sdlc/hooks/tests/run-smoke.sh`
**Result:** **PASS=44 FAIL=0** (deterministic, no `/sdlc` session, no network).

Regression — the two dependency suites still pass unchanged:
- `test_capture_subagent_lessons.sh` → PASS=27 FAIL=0
- `test_capture_user_correction.sh` → PASS=27 FAIL=0

---

## Isolation guarantees

- Every scenario writes to its own `mktemp` journal via `SDLC_JOURNAL_OVERRIDE`.
- The disable flag is redirected via `SDLC_LESSONS_FLAG_OVERRIDE`.
- The Haiku classifier is short-circuited via `SDLC_CLASSIFIER_STUB`, and
  `ANTHROPIC_API_KEY` is unset, so **no HTTPS call to api.anthropic.com is ever
  made** during the smoke run.
- The real journal at `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`
  is never touched (final assertion confirms).
- bash 3.2 compatible (macOS system bash — the only bash on this host; no
  `mapfile`, no `read -d`).

---

## Scenario 1 — SubagentStop against a REAL `/sdlc` transcript (keystone)

**Real source (audited):**
`~/.claude/projects/-Users-maorb-git-dev/52f55015-9148-4180-8c03-a92b81743323/subagents/agent-afd47cdc299c81709.jsonl`

This is an **actual `sdlc-plan-challenger` subagent run** (43 lines) whose final
assistant message carried a `## Lessons` block. The committed fixture
`tests/fixtures/real-subagent-transcript.jsonl` is a **byte-identical copy**
(same SHA-256: `a86d37d8b472545b7e4abf633c23aedda0651d09cb784f258ce5c7bf141d5249`),
so the test reproduces against the real data shape after the live transcript is
cleaned up. This validates the `.type=="assistant"` /
`message.content[].type=="text"` extraction against REAL data — the exact risk
CSI-638 flagged about hand-built fixtures.

The real lesson it captured (verbatim, truncated):

> Trigger: The researcher/plan framed chat auth as "Anthropic key / Bedrock" as
> if undecided, but the repo already defaults to a Bedrock LiteLLM proxy…
> Generalizable rule: When the product is mature, the challenger must check the
> actual config/auth code… Suggested fix type: instruction-edit. Suggested
> target: …/sdlc-plan-challenger.md

**Literal emitted event (field projection):**

```json
{"source":"agent-self-report","status":"raw","agent":"sdlc-plan-challenger","epic":null,"story":null,"phase":null,"extractor_run":null,"applied_commit":null}
```

Assertions (all pass): exactly 1 raw event; `status==raw`;
`source==agent-self-report`; `agent==sdlc-plan-challenger`; the exact 12-field
schema; `id` matches `evt_<date>_<time>_<6hex>`; evidence contains all four
verbatim `### Lesson` field labels AND the lesson's distinctive target text
(`sdlc-plan-challenger.md`); `trigger_summary` captured (`Bedrock`); hook exits 0.

---

## Scenario 2 — hook fires WITHOUT the model (the N4 assertion)

`capture-user-correction.sh` runs end-to-end with the classifier stubbed, so no
main orchestrator model and no network are in the loop — the hook decides and
writes alone.

**Literal emitted event (S2a, field projection + keys):**

```json
{"source":"user-correction","status":"raw","agent":null}
keys: ["agent","applied_commit","epic","evidence","extractor_run","id","phase","source","status","story","trigger_summary","ts"]
```

| Sub | Input | Expected | Result |
|-----|-------|----------|--------|
| 2a | `SDLC_CLASSIFIER_STUB=yes`, correction prompt | 1 raw `user-correction` event, NO model | 1 line, verbatim evidence ✓ |
| 2b | `SDLC_CLASSIFIER_STUB=no`, correction prompt | 0 events (veto honored) | 0 lines ✓ |
| 2c | ordinary prompt, no stub, no API key | keyword pre-filter bails before any classifier call → 0 events | 0 lines, exit 0 ✓ |
| 2d | `SDLC_CLASSIFIER_STUB=maybe` | 0 events (`maybe` is the drain-time gate, not the hook) | 0 lines ✓ |

**CSI-644 as-built contract:** the emitted event has the exact 12-field schema
and **no `classifier` field** — asserted on both S1 and S2a (`assert_schema`).

---

## Scenario 3 — toggle hard-gate (`.sdlc-lessons-disabled`)

With the flag file present, BOTH hooks no-op and exit 0:

| Sub | Hook | Input even though gated | Result |
|-----|------|-------------------------|--------|
| 3a | SubagentStop | the REAL well-formed transcript | 0 events, exit 0 ✓ |
| 3b | UserPromptSubmit | `STUB=yes` + correction prompt | 0 events, exit 0 ✓ |

---

## Scenario 4 — schema / robustness (hooks must never break the pipeline)

| Sub | Input | Expected | Result |
|-----|-------|----------|--------|
| 4a | transcript with no `## Lessons` | 0 events, exit 0 | ✓ |
| 4b | malformed `### Lesson` (missing `Suggested target`) | 0 events, `malformed` warning logged, exit 0 | ✓ |
| 4c | 2 well-formed + 1 malformed block | exactly 2 events | ✓ |
| 4d | corrupt / truncated JSONL | 0 events, exit 0 (no crash) | ✓ |
| 4e | missing transcript file | 0 events, exit 0 | ✓ |
| 4f | empty prompt to correction hook | 0 events, exit 0 | ✓ |

---

## Layer B (end-to-end `/sdlc` lifecycle scenarios) — status

The tech spec's Layer B (self-report → drain → extractor → proposal → approve →
Edit; near-dup suppression; mode-2 batching; etc.) requires a live `/sdlc`
session started AFTER the hooks were installed, and exercises the orchestrator
drain procedure in `commands/sdlc.md`. That is an **interactive** verification
and is out of scope for this automated, hermetic smoke script. The hook-side
contracts those flows depend on (event shape, source, status, schema, toggle,
robustness) are fully covered above by reading the actual journal. Layer B
should be run as a manual `/sdlc` session and its journal evidence appended here.

## Gaps / notes

- **No blockers found.** All dependency contracts the spec called out
  (`SDLC_JOURNAL_OVERRIDE`, `SDLC_CLASSIFIER_STUB`, `SDLC_LESSONS_FLAG_OVERRIDE`)
  are present and honored by the merged hooks.
- Host has only bash 3.2; the suite (and the hooks) are 3.2-clean.
