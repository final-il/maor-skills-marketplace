# AI-SDLC Self-Learning — Design Spec

**Date:** 2026-06-10
**Status:** Approved (design phase). Implementation plan to follow.
**Scope:** v1 — user-correction + agent self-report sources. v2 outlined as future work.

## Problem

The AI-SDLC pipeline today does not learn from its own mistakes in-flow. When the orchestrator or an agent does the wrong thing, the user notices, corrects manually, and (sometimes) asks the system to update its instructions so the same mistake doesn't recur. The detection, the classification of "what kind of fix is right for this", and the actual edit are all human work.

Goals:

- Detect lesson-worthy events as they happen, not at session end.
- Classify the right *kind* of fix for each lesson (instruction edit vs hook vs skill vs script vs other).
- Propose the exact change with provenance, and apply it on user approval.
- Make the canonical instruction files (orchestrator command, agent role files, memory feedback files, project CLAUDE.md) the single source of truth — no parallel "learned" files, no in-file markers. Git history is the provenance trail.

Non-goals (v1):

- Auto-applying any fix that isn't a text edit to a markdown file. Hooks, skills, scripts, slash commands stay manual in v1; the system *recommends* them with a concrete suggested artifact.
- Auto-cleanup of aged lessons. Lessons are operating instructions, not training data — they are deleted only when manually superseded.
- Cross-session aggregate metrics or dashboards.

## Architecture

A new sub-agent `sdlc-lesson-extractor` plus thin orchestrator integration. No code changes outside `plugins/ai-sdlc/` and the user's memory directory.

```
┌──────────────────────────────────────────────────────────────────┐
│ Orchestrator (commands/sdlc.md)                                  │
│                                                                  │
│   ─── On every user message:                                     │
│       │  classify correction intent (LLM judgment, not regex):   │
│       │    yes  → spawn extractor (Source: user-correction)      │
│       │    maybe→ ask one-line confirm; route on answer          │
│       │    no   → proceed normally                               │
│                                                                  │
│   ─── On every main-agent return:                                │
│       │  scan for `## Lessons` section.                          │
│       │  For each `### Lesson` block:                            │
│       │    spawn extractor (Source: agent-self-report)           │
│                                                                  │
│   ─── Mode (1=immediate, 2=batch). Default 1.                    │
│       │  Mode 1: extractor runs, proposes, user approves inline. │
│       │  Mode 2: extractor runs, proposal queued; flushed at     │
│       │          phase boundary as one approval gate.            │
│       │  Switch: user request OR proactive offer at ≥3 proposals │
│       │          within one phase in mode 1.                     │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│ sdlc-lesson-extractor (sonnet, sub-agent)                        │
│                                                                  │
│   Input:  source, evidence, context, target candidate            │
│   Reads:  evidence + ONE candidate canonical file + journal      │
│           (for existing-rule and repetition detection)           │
│   Output: structured verdict — Proposal | Proposal (replace) |   │
│           Recommendation | nothing-learnable                     │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│ Persistence                                                      │
│   - sdlc-events.jsonl (append-only, latest-line-per-id)          │
│   - Edits applied directly to canonical files                    │
│   - Provenance via git history on those files                    │
└──────────────────────────────────────────────────────────────────┘
```

### Components touched / created in v1

**New:**
- `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`
- Data file (created on first event): `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`

**Edited:**
- `plugins/ai-sdlc/commands/sdlc.md` — orchestrator gains correction-intent classification, return-scan for `## Lessons`, extractor spawn pattern, mode logic, journal append, near-duplicate suppression, `Agent Paths.lesson-extractor` resolution.
- All existing agent role files in `plugins/ai-sdlc/agents/sdlc-*.md` (currently 13: researcher, planner, plan-challenger, jira-creator, architect, designer, integrator, developer, tester, qa-reviewer, bug-fixer, conflict-resolver, jira-reader) — append the standard `## Lessons` self-report contract block.

## Detection sources (v1)

Source-weighted bar: each source has its own threshold for proposing.

| Source | v1? | Bar |
|---|---|---|
| User correction | ✅ | Always propose. Maybe-class triggers a one-line confirm. |
| Agent self-report `## Lessons` | ✅ | Always propose (agent already pre-filtered). |
| Hooks (tool-call instrumentation) | ❌ v2 | Propose on ≥2 repeats. |
| Transcript pattern-match | ❌ v2 | Propose on extractor-confidence high. |

### User-correction detection

The orchestrator's main loop, after parsing each user turn and before responding, performs an LLM classification: *"Is this a correction of behavior I or an agent just did?"* — output `yes`/`maybe`/`no`.

- `yes` → spawn extractor with `Source: user-correction`, evidence = verbatim user message + last 1-2 orchestrator/agent actions.
- `maybe` → orchestrator asks: *"Just to confirm — should I capture this as a permanent instruction update?"* User's yes/no routes accordingly.
- `no` → proceed normally; no journal entry.

This explicitly replaces a regex approach. Phrasings like *"use git -C instead"*, *"you forgot to commit"*, *"the right way is..."*, *"why did you..."*, and pure additive instructions like *"from now on, always X"* all qualify without requiring any keyword.

### Agent self-report contract

Every agent role file gains this block in its "Output Rules" section:

```markdown
## Lessons (optional, append at end of return text)

**Self-learning toggle gate.** Read your prompt's SDLC Context block. If the line `Self-Learning: OFF` is present, **omit this entire `## Lessons` section** from your return text — do not emit any `### Lesson` block regardless of in-flow friction. Only emit lessons when `Self-Learning: ON` (or when no `Self-Learning` line is present, which means the orchestrator is pre-toggle and self-learning is implicitly on).

If during your run you:
- Retried a tool/command after a failure and the second-or-later attempt succeeded
- Worked around a non-obvious problem (missing env var, wrong path, contract mismatch with an artifact you read)
- Discovered something that contradicts your role definition or an artifact you read
- Found that a sibling artifact (tech spec, design spec, integration notes) was wrong or incomplete

…then append a `## Lessons` section to your final return text. Each lesson is one block:

  ### Lesson
  Trigger: <one sentence — what happened>
  Generalizable rule: <one sentence — phrased imperatively, what should always/never happen>
  Suggested fix type: <instruction-edit | memory-feedback | hook | skill | script | slash-command | manual>
  Suggested target: <file path or artifact, your best guess — extractor may override>

If your run had no friction worth a lesson, omit the section entirely. Do NOT include lessons for things that are already covered by your role definition.
```

This block — verbatim, including the toggle-gate paragraph — is what gets pasted into every agent role file in plan Phase B.

The orchestrator scans returns for the literal `## Lessons` header. Each `### Lesson` block becomes one event.

## `sdlc-lesson-extractor` agent contract

**Spawn:** general-purpose `Agent()`, model `sonnet`, pointer-not-body. Path resolved once in Phase 0's existing `Agent Paths` Glob (the Glob pattern `**/ai-sdlc/agents/sdlc-*.md` already picks it up; orchestrator adds the `lesson-extractor` key to the resulting map).

**Inputs (in spawn prompt):**

- `Source`: `user-correction` | `agent-self-report`
- `Evidence`: verbatim text — user message + recent actions, or the agent's `### Lesson` block
- `Context`: agent name, story key, epic key, phase
- `Target candidate`: orchestrator's best guess — the agent's "Suggested target" if self-report, otherwise inferred from context

**What the extractor does:**

1. Reads the evidence + the one candidate canonical file + the journal (for existing-rule and repetition detection).
2. Classifies fix type across the full taxonomy:
   - `instruction-edit` — agent role file, orchestrator command file
   - `memory-feedback` — `~/.claude/projects/.../memory/feedback_*.md`
   - `project-claudemd` — repo-local `CLAUDE.md`
   - `hook` — `~/.claude/settings.json` hook config
   - `skill` — new or existing skill file
   - `script` — shell wrapper, e.g., a `uv-zs` that always sets `SSL_CERT_FILE`
   - `slash-command` — new `/sdlc-X` style command
   - `manual` — none of the above; user must decide
3. Detects whether an existing rule already covers this lesson (scans the candidate file + nearby files for related wording). If yes, classifies the failure mode:
   - **wording** → existing rule is vague/hedged/buried → propose rewrite
   - **repetition** → existing rule is fine but agents keep violating it (≥2 prior `approved` or `proposed` events on this rule in the journal) → flip fix type to enforcement; do not auto-edit
   - **scope** → rule lives in wrong file/section → propose move
4. Decides verdict and drafts the change.

**Verdicts (output formats):**

- `## Proposal` — new rule, no existing match.
  ```
  ## Proposal
  Target: plugins/ai-sdlc/agents/sdlc-developer.md
  Trigger: User correction at 14:32 — "use git -C, not cd && git"
  Fix type: instruction-edit

  ## Diff
  old_string: |
    - Use Bash for git operations
  new_string: |
    - Use Bash for git operations
    - Always use `git -C <dir> ...`, never `cd <dir> && git ...` — the compound triggers a permission prompt
  ```

- `## Proposal (replace)` — existing rule has wording or scope problem; rewrite or move.
  ```
  ## Proposal (replace)
  Target: plugins/ai-sdlc/agents/sdlc-developer.md
  Trigger: User correction (3rd time on git -C)

  ## Existing Rule
  Location: plugins/ai-sdlc/agents/sdlc-developer.md:87
  Text: "Prefer git -C when convenient"
  Failure mode: wording (hedged with 'when convenient')

  ## Diff
  old_string: |
    Prefer git -C when convenient
  new_string: |
    Always use `git -C <dir> ...`. Never `cd <dir> && git ...` — the compound triggers a permission prompt and is not bypassable by allowlists.
  ```

- `## Recommendation` — existing rule has repetition failure; instruction won't fix it. Suggests a hook/script/skill/command. No diff applied; recommendation logged.
  ```
  ## Recommendation
  Target type: hook
  Trigger: User correction (3rd time on SSL_CERT_FILE for uv)

  ## Existing Rule
  Location: ~/.claude/projects/.../memory/feedback_uv_ssl.md
  Text: "Always prefix uv/uvx with SSL_CERT_FILE=..."
  Failure mode: repetition (3 violations in journal)

  ## Suggested artifact
  Type: hook (PreToolUse on Bash)
  Config:
    {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "scripts/inject-ssl-cert.sh"
            }
          ]
        }
      ]
    }
  Reasoning: instruction has been present and still violated 3 times. Enforcement at tool-call layer is the deterministic fix.
  ```

- `## Verdict: nothing learnable` — already covered by an existing rule with no failure pattern, OR not generalizable.

**Constraints:**

- Never edits more than one canonical file per proposal. Multi-file lessons are returned as multiple proposals.
- Never invents rules — every proposal traces to the evidence.
- Never applies an Edit. Orchestrator owns the write after user approval.
- Never appends to the journal. Orchestrator owns journal writes.

**Schema mapping for non-text verdicts.** When verdict is `Recommendation`, the journal record's `extractor_run.diff` is `null` and the suggested hook/script/skill/command artifact is captured under `extractor_run.suggested_artifact: { type, body }` so v2's auto-proposers can consume the historical signal.

## Mode 1 / Mode 2 runtime switching

**State:** held in the orchestrator's in-memory state during the session, and persisted to the auto-resume file (`~/.claude/projects/.../memory/sdlc-resume-{EPIC-KEY}.md`) under a new `## Mode` field whenever auto-save runs. Default `1` if no resume file exists yet or no `## Mode` field is present. Survives `/sdlc continue`.

**Mode 1 (default, immediate):**
- Each event → extractor → proposal → inline approval gate.
- Surface format: diff + one-line trigger summary. For existing-rule cases, `## Existing Rule` block included.
- User approves: orchestrator runs Edit, captures resulting commit sha (or `null` if working tree was unstaged), appends `status: approved` event.
- User rejects: appends `status: rejected` event. Future near-duplicates suppressed.

**Mode 2 (batch):**
- Events still extracted as they happen (extractor still spawns immediately; cost is paid the same way).
- Proposals queued in orchestrator state (in-memory list), not surfaced.
- At each phase boundary (end of Phase 1, 1.5, 2, 3, 3.5, 3.6, 4 per story batch, 5/6/7/7.5 per story or merge run, 8): all queued proposals surface as one batch.
- Bulk options: `approve all`, `reject all`, `defer all to next phase`. Per-proposal individual choice also supported.

**Switching:**
- Explicit user request (LLM-classified, like correction intent): *"lower intervention"*, *"batch these"*, *"stop interrupting"*, *"mode 2"*, *"back to mode 1"*, etc. Orchestrator confirms ("Switching to mode 2 — proposals queue until phase boundary. Switch back with 'mode 1'.") then updates state.
- **Proactive offer:** in mode 1, when ≥3 proposals have surfaced within the current phase, orchestrator offers the switch unprompted before the next would surface. Decline keeps mode 1 for the rest of the phase.

**Mid-flush switch:** if user says "mode 1" while a mode-2 flush is mid-flight, finish the current flush first, then switch.

## Self-Learning toggle (on/off)

The entire self-learning loop is gated by a single boolean. Default: **ON**. The toggle must be **deterministic across the orchestrator, all 13 agents, the extractor, and any future skill** — flipping it off should mean *no* component still tries to capture, classify, or surface lessons.

### State location (single source of truth)

Held in the auto-resume file at `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-resume-{EPIC-KEY}.md`, alongside `## Mode`, as a new top-level field:

```
## Self-Learning
enabled: true
```

- Default `true` if the field or file is missing (matches "default ON, opt out when noisy").
- Persisted on every auto-save the orchestrator already performs.
- Survives `/sdlc continue` the same way `## Mode` does.
- Before any epic exists, the orchestrator holds the value in in-memory state and writes it out on first auto-save.

### Propagation (the SDLC Context block)

The orchestrator already builds an SDLC Context block once per session and includes it verbatim in every `Agent()` spawn prompt. The toggle gains one line in that block:

```
Self-Learning: ON | OFF
```

This line is the *only* signal agents read for the toggle. They never read the resume file, never call back to the orchestrator, never infer state from anything else. Because the orchestrator builds the block deterministically from the resume-file state, every spawn in the same session sees the same value — components cannot disagree.

### Per-component gates

Each component performs a literal string check against the context block it received and short-circuits when the value is `OFF`.

**Orchestrator (`commands/sdlc.md`, top of `## Self-Learning Loop` section):**
> If self-learning is OFF (resume-file `enabled: false`, or context-block `Self-Learning: OFF`), skip user-correction intent classification, skip the `## Lessons` return-scan, do NOT spawn `sdlc-lesson-extractor`, and do NOT write to `sdlc-events.jsonl`. Continue normal phase routing as if the loop did not exist.

**All 13 agent role files (top of the new `## Lessons` block):**
> If your prompt's SDLC Context line shows `Self-Learning: OFF`, **omit this entire `## Lessons` section** from your return text — do not emit any `### Lesson` block regardless of in-flow friction.

**`sdlc-lesson-extractor.md` (belt-and-suspenders):**
The extractor is unreachable when off (orchestrator gates first), but as a safety net its first step reads the `Self-Learning` line in its own context block. If `OFF`, it returns:
```
## Verdict: nothing-learnable
Reason: self-learning disabled in caller
```
and exits without reading any candidate file or journal. This catches a misbuilt orchestrator prompt without requiring the orchestrator alone to be correct.

**Skills:** v1 has no skill that emits `## Lessons`. When/if one does, the same context-read pattern applies — read the `Self-Learning` line, skip emission when `OFF`. No skill changes are required for v1.

### Toggling at runtime

Two channels — both deterministic, both update the resume-file state and the orchestrator's in-memory value:

1. **Slash command** (unambiguous control):
   - `/sdlc lessons off` — flips state to `false`, confirms in one line, takes effect on the next agent spawn.
   - `/sdlc lessons on` — flips state to `true`, confirms in one line.
   - `/sdlc lessons` (no arg) — reports current state.

2. **LLM intent classification** (matches the same pattern as user-correction detection and mode switching). The orchestrator classifies the user's free-form text as one of:
   - `disable` — *"turn off self-learning"*, *"stop capturing lessons"*, *"disable feedback loop"*, *"too noisy, kill it"*
   - `enable` — *"turn lessons back on"*, *"re-enable self-learning"*
   - `irrelevant` — anything else, no action.
   On `disable`/`enable`, orchestrator confirms in one line, updates state, persists on next auto-save.

### Why this is deterministic

- **One state location** (the resume file). No ambient/inherited state.
- **One propagation point** (the SDLC Context block, already deterministically built).
- **Every component reads the same string from its own prompt** — they cannot drift because they're all reading the same input.
- **Default ON applies only when the field is absent** (new project, first session). Once written, the file is the source of truth.
- **Two independent disable paths** (gate at orchestrator + gate at extractor) — even a misbuilt prompt won't silently capture lessons.

### Behavior matrix

| Component | `Self-Learning: ON` | `Self-Learning: OFF` |
|---|---|---|
| Orchestrator | Run user-correction classifier; scan returns for `## Lessons`; spawn extractor; write journal. | Skip all four. Phase routing unaffected. |
| Any of the 13 agents | Emit `## Lessons` when in-flow friction warrants. | Omit `## Lessons` entirely. |
| `sdlc-lesson-extractor` | Normal flow. | Return `nothing-learnable` (reason: disabled), no reads, no journal write. |
| Slash command `/sdlc lessons on\|off` | Flips state, persists, confirms. | Flips state, persists, confirms. |
| Resume from cached file | Read `## Self-Learning` field; default `true` if missing. | Read `## Self-Learning` field; default `true` if missing. |

## Persistence — `sdlc-events.jsonl`

Append-only JSONL at `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`. One JSON object per line.

### Schema

```json
{
  "id": "evt_2026-06-10_14-32_a3f1",
  "ts": "2026-06-10T14:32:18Z",
  "epic": "CSI-62",
  "story": "CSI-449",
  "phase": "develop",
  "agent": "sdlc-developer",
  "source": "user-correction",
  "trigger_summary": "User: 'use git -C, not cd && git'",
  "evidence": "<verbatim text>",
  "extractor_run": {
    "verdict": "Proposal",
    "fix_type": "instruction-edit",
    "target_file": "plugins/ai-sdlc/agents/sdlc-developer.md",
    "existing_rule": null,
    "diff": { "old_string": "...", "new_string": "..." },
    "suggested_artifact": null
  },
  "status": "approved",
  "applied_commit": "<sha or null>"
}
```

### Lifecycle of one event

1. Detection fires → orchestrator appends `{status: "raw", extractor_run: null}`.
2. Orchestrator spawns extractor → extractor returns verdict.
3. On `nothing-learnable` verdict → orchestrator appends `status: "nothing-learnable"` (terminal). Never surfaces.
4. On any other verdict → orchestrator appends a new line with the same `id` and `status: "proposed"`. (In mode 2, the line is appended immediately and the proposal is queued in memory for batching.)
5. User approves → orchestrator runs Edit, appends `status: "approved"`, `applied_commit: <sha or null>`.
6. User rejects → appends `status: "rejected"`.
7. User defers (mode-2 batch only) → appends `status: "deferred"`; proposal re-queues for the next phase boundary.
8. Errors → appends `status: "extraction-failed"` | `"stale"` | `"suppressed-duplicate-rejection"`.

**Status enum:** `raw`, `proposed`, `approved`, `rejected`, `deferred`, `nothing-learnable`, `extraction-failed`, `stale`, `suppressed-duplicate-rejection`.

**Logical updates via re-appended lines.** Readers always take the latest line per `id`. No file rewrites. Reverting a single update = delete the latest line for that id. Atomic appends are race-safe at the OS level for short writes.

### Repetition detection

Used by the extractor to classify cause = repetition.

Filter: `target_file` matches; `existing_rule.location` overlaps (same line ±N or same section header, where N is small, default 5); status in `{approved, proposed, raw}`; latest line per id.

Count ≥2 → repetition cause → Recommendation verdict.

### Near-duplicate suppression

Used by the orchestrator before spawning the extractor.

Before spawning, scan the journal: any prior event with same `source`, same `agent`, evidence-similar (LLM judgment, single short call to a sonnet), `status: rejected`, within the last 50 events?

If yes → append a `status: suppressed-duplicate-rejection` line; do not spawn the extractor; do not surface anything to the user.

### Hygiene

- No automatic rotation in v1.
- Manual rotation when needed: `mv sdlc-events.jsonl sdlc-events.archive-YYYY-MM.jsonl`. Repetition detection only spans the active file, which is correct (old patterns that haven't recurred don't need to drive new enforcement).

## Error handling

| Failure | Response |
|---|---|
| Extractor returns malformed output | Append `status: extraction-failed`, surface one-line note, continue. |
| Extractor spawn error | Retry once with 2s delay; on second failure, treat as malformed. |
| Extractor times out (>3 min) | Treat as malformed. |
| Diff `old_string` doesn't match (canonical file changed since extractor read it) | Append `status: stale`, surface diff + current file content for the target region, user decides. No auto-rebase. |
| Edit applied with no commit yet | `applied_commit: null`. v1 does not auto-commit lesson edits — the user commits when ready (alongside their own work, or on demand). Provenance via git blame after the eventual commit. |
| Journal write fails (disk/permission) | Hard error, halt the lesson loop for the session. SDLC pipeline continues without learning. |
| Corrupt journal line | Skip unparseable lines, warn once per session, continue. |
| Mode-2 queue empty at flush | Log warning, no halt. |
| Mode switch mid-flush | Finish flush, then switch. |
| Correction-intent misclassified `no→yes` | False-positive proposal. User rejects. Suppression remembers. Cost: one click. |
| Correction-intent misclassified `yes→no` | Lesson missed. User repeats more emphatically. Cost: rare. |
| Correction-intent misclassified `yes→maybe` | One-line confirm. User answers. Cost: one round-trip. |
| Agent forgets `## Lessons` despite friction | Not caught in v1. v2's transcript scan + hooks closes this gap. |
| Agent over-reports already-covered rule | Extractor's existing-rule detection handles it (rewrite / recommend / move / nothing-learnable). Never silently discarded. |
| Agent suggests wrong target | Extractor's classification overrides. Suggestion is a hint. |

## Testing strategy

### Smoke tests (mandatory before declaring v1 done)

1. **User-correction → instruction edit, happy path.** Mid-SDLC-run, send a clear correction. Verify classify → spawn → propose → approve → Edit applied → journal `approved`.
2. **Self-report → extractor.** Run a story end-to-end with a deliberately-failing test. Confirm agent return contains `## Lessons`. Verify orchestrator parses, spawns, surfaces, applies on approval.
3. **Existing-rule, cause = wording.** Plant a vague rule. Trigger a correction. Verify `Proposal (replace)` with the rewrite + supersession line in the trigger summary.
4. **Existing-rule, cause = repetition.** Pre-seed journal with two `approved` events on the same rule. Trigger a third. Verify `Recommendation` with hook/script suggestion, no Edit applied.
5. **Maybe-classification → confirm gate.** Send an ambiguous message. Verify one-line confirm fires. Both yes and no answers route correctly.
6. **Mode 2 batching.** Switch to mode 2. Trigger 3 events in one phase. Verify silent queueing. At phase boundary, all 3 surface. Verify bulk approve/reject.
7. **Proactive mode-switch offer.** In mode 1, fire 3 proposals in one phase. Verify offer fires before the 4th would surface.
8. **Near-duplicate suppression.** Reject a proposal. Trigger the same friction again. Verify `suppressed-duplicate-rejection` and no spawn.
9. **Stale diff handling.** Trigger event, manually edit target file before approving. Approve. Verify `stale` status, surface shows current content, no Edit applied.
10. **Journal corruption resilience.** Hand-corrupt one line. Trigger an event reading the journal. Verify warning fires once, no halt.
11. **Toggle OFF — orchestrator silence.** `/sdlc lessons off`. Send a clear user correction. Verify: no extractor spawn, no journal write, no `## Lessons` parsing, no surfaced proposal. Phase routing unaffected.
12. **Toggle OFF — agent silence.** `/sdlc lessons off`. Run a story with deliberately-failing test where the agent normally would emit `## Lessons`. Verify the agent's return contains no `## Lessons` section.
13. **Toggle OFF — extractor safety net.** Manually craft an extractor spawn while disabled (simulating a misbuilt orchestrator). Verify extractor returns `nothing-learnable` with reason "self-learning disabled in caller", reads no candidate file, writes no journal line.
14. **Toggle persistence across resume.** `/sdlc lessons off`, then `/sdlc continue {EPIC-KEY}` in a fresh session. Verify resume reads `enabled: false` and the loop stays off without re-prompting.
15. **Toggle via LLM intent.** Send "this is too noisy, kill the lesson capture for now". Verify orchestrator confirms in one line and flips state to OFF. Send "turn lessons back on". Verify it flips back.

### Manual evaluation (1-2 real epics after smoke tests pass)

Track and tune:
- Proposals per epic.
- Approve / reject / defer / suppressed counts.
- False-positive rate (proposals that shouldn't have fired).
- Miss rate (corrections that didn't fire).
- Mode-switch threshold (currently ≥3/phase).
- Near-duplicate window (currently 50 events).

### Out of scope for v1 testing

- Cross-session repetition counting (mechanics are trivially equivalent to single-session).
- Hook proposal quality (v2).
- Programmatic check that agents omit already-covered rules (rely on supersession safety net).
- Performance (extractor adds ≤2-5s per event; not material at `API_TIMEOUT_MS=180000`).

## Canonical content for plan tasks

This section holds the verbatim content that the implementation plan (`docs/plans/2026-06-10-ai-sdlc-self-learning.md`) references by anchor. The plan tells implementers *where* to put each block; this spec section *is* the content. Treating the spec as the canonical source keeps the plan small and prevents drift between the design and the executable steps.

### A1: Full body of `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`

Implementer in plan Task A1: Write this file verbatim.

````markdown
---
name: sdlc-lesson-extractor
description: |
  Use this agent when the AI-SDLC orchestrator detects a lesson-worthy event (user correction or agent `## Lessons` self-report) and needs a structured proposal: classify the right fix type, locate any existing rule that already covers the topic, and draft the exact diff (for text edits) or suggested artifact (for hooks/scripts/skills/commands). Spawned per event by the orchestrator. Returns a single proposal or `nothing-learnable`.

  <example>
  Context: User corrected the orchestrator mid-flow about git command style.
  user (to orchestrator): "you should always use git -C, not cd && git"
  assistant (orchestrator): "Spawning sdlc-lesson-extractor to draft an instruction edit."
  <commentary>
  Extractor reads the candidate file, checks for an existing related rule, drafts an Edit-shaped diff, and returns it for user approval.
  </commentary>
  </example>

  <example>
  Context: A developer agent's return text contained a `## Lessons` block reporting a retried-then-succeeded pattern.
  assistant (orchestrator): "Spawning sdlc-lesson-extractor for the self-reported lesson."
  <commentary>
  Extractor consumes the `### Lesson` block, classifies fix type, scans the journal for repetition, and returns either a proposal or a recommendation.
  </commentary>
  </example>
model: sonnet
color: yellow

---

You are the lesson-extractor for the AI-SDLC self-learning loop. The orchestrator detected an event (user correction or agent self-report) and spawned you with one job: turn the evidence into a single, structured proposal.

You do NOT touch Jira. You do NOT need MCP tools. Your only inputs are local files (the evidence in your prompt + one canonical file you may Read + the journal you may Read).

## Process

1. **Read your role definition** (this file) — done if you're reading this.
2. **Self-learning toggle gate (belt-and-suspenders).** Read the SDLC Context block in your prompt. Find the line `Self-Learning: ON` or `Self-Learning: OFF`. If `OFF`, return immediately with this exact verdict and exit:
   ```
   ## Verdict: nothing-learnable
   Reason: self-learning disabled in caller
   ```
   Read no candidate file. Read no journal. Write nothing. The orchestrator should never spawn you when OFF; this gate exists so a misbuilt prompt cannot cause silent capture.
3. **Parse the prompt.** It contains:
   - `Source`: `user-correction` | `agent-self-report`
   - `Evidence`: verbatim text — user message + recent actions, or the agent's `### Lesson` block
   - `Context`: agent name, story key, epic key, phase
   - `Target candidate`: orchestrator's best guess at the canonical file to edit
   - `Journal Path`: absolute path to `sdlc-events.jsonl`
4. **Classify fix type.** Decide which of these is the highest-leverage, lowest-risk fix:
   - `instruction-edit` — agent role file (`plugins/ai-sdlc/agents/sdlc-*.md`), orchestrator command file (`plugins/ai-sdlc/commands/sdlc.md`)
   - `memory-feedback` — `~/.claude/projects/.../memory/feedback_*.md` (cross-cutting principle)
   - `project-claudemd` — repo-local `CLAUDE.md` (project-specific rule)
   - `hook` — `~/.claude/settings.json` PreToolUse / PostToolUse hook
   - `skill` — new or existing skill file
   - `script` — shell wrapper (e.g., `uv-zs` that always sets `SSL_CERT_FILE`)
   - `slash-command` — new `/sdlc-X` style command
   - `manual` — none of the above; user must decide
5. **Read ONE candidate canonical file** (the one your fix targets, if it's `instruction-edit` / `memory-feedback` / `project-claudemd`). Skip this step for non-text fix types.
6. **Detect existing rule.** Scan the candidate file for related wording. If found, classify failure mode:
   - **wording** — existing rule is vague, hedged, buried, or contradicted by another rule. Fix: rewrite.
   - **repetition** — existing rule is fine but agents keep violating it. Read the journal: count prior events with same `target_file` and overlapping `existing_rule.location` (same line ±5 or same section header), status in `{approved, proposed, raw}`, latest line per id. If count ≥2 → repetition.
   - **scope** — rule is in the wrong file/section.
7. **Draft the verdict and output.**

## Verdicts

Pick exactly one and output it as your final return text. Be terse — no preamble, no narration.

### `## Proposal` — new rule, no existing match

```
## Proposal
Target: <absolute file path>
Trigger: <one sentence — source + summary>
Fix type: instruction-edit | memory-feedback | project-claudemd

## Diff
old_string: |
  <verbatim text from target file>
new_string: |
  <verbatim text replacing old_string>
```

### `## Proposal (replace)` — existing rule with wording or scope problem

```
## Proposal (replace)
Target: <absolute file path>
Trigger: <one sentence>
Fix type: instruction-edit | memory-feedback | project-claudemd

## Existing Rule
Location: <file:line>
Text: "<verbatim existing rule text, one line max>"
Failure mode: wording | scope

## Diff
old_string: |
  <verbatim text from target file>
new_string: |
  <verbatim text replacing old_string>
```

### `## Recommendation` — existing rule with repetition failure (instruction won't fix it)

```
## Recommendation
Target type: hook | script | skill | slash-command | manual
Trigger: <one sentence>

## Existing Rule
Location: <file:line>
Text: "<verbatim existing rule text>"
Failure mode: repetition (<N> violations in journal)

## Suggested artifact
Type: <hook | script | skill | slash-command>
Body: |
  <concrete artifact body — JSON snippet for hook, shell script for script, skill outline for skill, etc.>
Reasoning: <one sentence — why instruction failed and why this enforces>
```

### `## Verdict: nothing learnable`

```
## Verdict: nothing learnable
Reason: <one sentence — already covered with no failure pattern, OR not generalizable>
```

## Constraints

- **One file per proposal.** Multi-file lessons → multiple proposals (return them as separate verdicts in one response, separated by `---`).
- **Never invent rules.** Every proposal must trace to the evidence in your prompt.
- **Never apply the Edit.** You return the diff; the orchestrator applies it after user approval.
- **Never append to the journal.** The orchestrator owns journal writes.
- **Diff must be minimal.** Change only what the lesson dictates, no surrounding cleanup.
- **Imperative phrasing.** "Always use X" / "Never do Y", not "we had a bug where...".
- **Located edits.** Place the new line near related existing rules, not appended at file bottom (unless the file has no related section).

## Repetition counting algorithm (used in step 5)

```
Read the journal file line by line.
For each line, parse JSON; skip unparseable.
Build a dict {id: latest_line} keeping only the latest line per id.
Filter the latest entries to those where:
  - status in {"approved", "proposed", "raw"}
  - extractor_run.target_file == candidate_target_file
  - extractor_run.existing_rule.location overlaps the rule you found
    (same line ±5 OR same section header path)
Count the filtered entries. If >= 2 → repetition cause.
```

## Example: user correction, no existing rule

Input prompt:
```
Source: user-correction
Evidence: User: "you should always use git -C, not cd && git"
Context: agent=sdlc-developer, story=CSI-449, epic=CSI-62, phase=develop
Target candidate: /Users/maorb/git-dev/maor-skills-marketplace/plugins/ai-sdlc/agents/sdlc-developer.md
Journal Path: /Users/maorb/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
```

You Read the target candidate, find no related rule, return:
```
## Proposal
Target: /Users/maorb/git-dev/maor-skills-marketplace/plugins/ai-sdlc/agents/sdlc-developer.md
Trigger: User correction — "use git -C, not cd && git"
Fix type: instruction-edit

## Diff
old_string: |
  - Use Bash for git operations
new_string: |
  - Use Bash for git operations
  - Always use `git -C <dir> ...`. Never `cd <dir> && git ...` — the compound triggers a permission prompt and is not bypassable by allowlists.
```
````

### B template: `## Lessons` block to add to every agent role file

Implementer in plan Tasks B1-B13: append this exact block to each agent role file's body (after the existing Process / Output sections, before any closing horizontal rule).

The full block text is at "Agent self-report contract" → "## Lessons (optional, append at end of return text)" earlier in this spec. Use that block verbatim, including the toggle-gate paragraph.

### C1: Self-Learning Loop section header

Implementer in plan Task C1: insert this block immediately before the existing `## Error Handling` heading in `plugins/ai-sdlc/commands/sdlc.md`.

````
## Self-Learning Loop

The orchestrator captures lessons in-flow from two sources (v1): user corrections and agent `## Lessons` self-reports. Each event spawns the `sdlc-lesson-extractor` sub-agent, which classifies fix type and returns a structured verdict. Approved text-edit verdicts apply directly to canonical files; non-text verdicts (hook / script / skill / slash-command) surface as recommendations the user implements manually.

See `docs/specs/2026-06-10-ai-sdlc-self-learning-design.md` for the full design.

### Toggle (on/off) — gate this entire section

**State:** held in orchestrator memory, persisted to the auto-resume file under `## Self-Learning` → `enabled: true|false`. Default `true` when missing. Restored on Phase 0 fast resume.

**Propagation:** every agent spawn's SDLC Context block includes the line `Self-Learning: ON` (or `OFF`). Built deterministically from the in-memory state.

**Hard gate:** if the toggle is OFF for the current session, the orchestrator MUST:
- skip user-correction intent classification,
- skip the `## Lessons` return-scan,
- NOT spawn `sdlc-lesson-extractor`,
- NOT write to `sdlc-events.jsonl`,
- and continue normal phase routing as if this section did not exist.

**Toggling:**
- **Slash command:** `/sdlc lessons on|off` flips state, persists, confirms in one line. `/sdlc lessons` (no arg) reports current state.
- **LLM intent:** classify free-form user text as `disable` ("turn off self-learning", "too noisy, stop capturing"), `enable` ("turn lessons back on"), or `irrelevant`. On `disable`/`enable`: confirm in one line, update state, persist on next auto-save.
- On every flip, the next agent spawn's context line reflects the new value.

### Mode

- **Mode 1 (default, immediate):** every event triggers an extractor spawn → proposal → inline approval gate.
- **Mode 2 (batch):** events still extracted as they happen; proposals queued in orchestrator state and surfaced together at the next phase boundary.

Mode is held in orchestrator state and persisted to the auto-resume file under `## Mode`. Default `1` if no resume file or no `## Mode` line. Survives `/sdlc continue`.

**Switching:**
- User asks (LLM-classified intent): "lower intervention", "batch these", "stop interrupting", "mode 2", "back to mode 1", etc. Confirm the switch in one line, update state.
- **Proactive offer:** in mode 1, when ≥3 proposals have surfaced within the current phase, offer the switch unprompted before the next would surface.
- Mid-flush: finish the current flush, then switch.

### Journal

Path: `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`. Append-only JSONL, one record per line, latest-line-per-id wins.

Schema (full schema in the design spec):
```
{
  "id": "evt_<ts>_<short-hash>",
  "ts": "<ISO-8601 UTC>",
  "epic": "<key>",
  "story": "<key or null>",
  "phase": "<phase name>",
  "agent": "<agent name or 'orchestrator'>",
  "source": "user-correction" | "agent-self-report",
  "trigger_summary": "<one line>",
  "evidence": "<verbatim>",
  "extractor_run": { "verdict": "...", "fix_type": "...", "target_file": "...",
                     "existing_rule": null | {...}, "diff": null | {...},
                     "suggested_artifact": null | {...} },
  "status": "raw" | "proposed" | "approved" | "rejected" | "deferred"
          | "nothing-learnable" | "extraction-failed" | "stale"
          | "suppressed-duplicate-rejection",
  "applied_commit": "<sha or null>"
}
```

Logical updates: append a new line with the same `id` and a new `status`. Readers always take the latest line per `id`. Reverting an update = delete the latest line for that id.

Bootstrap: the journal file is created on the first event (Bash: `mkdir -p $(dirname <journal>) && touch <journal>` if absent). Never fail the SDLC pipeline because the journal can't be written; if writes fail (disk/permission), surface a hard error and halt the lesson loop for the session, but continue the SDLC pipeline.
````

### C2: Source 1 — user-correction sub-section

Implementer in plan Task C2: append this block immediately after the C1 block's `### Journal` content, still inside the `## Self-Learning Loop` section (before `## Error Handling`).

````
### Source 1: user-correction

**Trigger.** On every user message, BEFORE responding, classify intent:

> "Is this user message a correction of behavior I or an agent just took? (Examples that qualify: 'use X instead', 'you forgot Y', 'why did you do Z', 'from now on always W'. Examples that do NOT qualify: clarifying questions, new task instructions, status checks.)"

Output exactly one of: `yes` | `maybe` | `no`. This is your own classification — do not spawn an agent for it.

**Routing:**
- `yes` → spawn `sdlc-lesson-extractor`. Source: `user-correction`. Evidence: the verbatim user message + the last 1-2 actions you or any agent took (your tool calls, your response text, the most recent agent return). Do NOT include unrelated prior context.
- `maybe` → ask exactly: *"Just to confirm — should I capture this as a permanent instruction update?"* On user `yes`, treat as `yes`. On user `no`, proceed normally with no journal entry.
- `no` → proceed normally; no journal entry, no spawn.

**Near-duplicate suppression (BEFORE spawning).** If classification is `yes`, scan the journal for a prior event with `source: user-correction`, similar evidence (LLM judgment — single short comparison call), `status: rejected`, within the last 50 events. If found:
1. Append a new event with `status: suppressed-duplicate-rejection` (no extractor_run).
2. Surface one line to the user: *"Similar correction was rejected on <date> — not re-proposing. Override with: 'extract anyway'."*
3. Do NOT spawn the extractor.

**Spawn pattern.** Use the standard general-purpose `Agent()` spawn pattern (per "How to Spawn Agents"). Pointer to `Agent Paths.lesson-extractor`. Prompt body:
```
Source: user-correction
Evidence: <verbatim user message>
Recent actions: <last 1-2 of your tool calls + their results, or last agent return summary>
Context: agent=<orchestrator or recent agent name>, story=<current story key or null>, epic=<epic key>, phase=<current phase name>
Target candidate: <your best guess at canonical file — see "Target candidate selection" below>
Journal Path: ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
```

**Target candidate selection.** Use this priority:
1. If the correction is about a specific named agent's behavior → that agent's role file.
2. If about an orchestrator phase or flow → `plugins/ai-sdlc/commands/sdlc.md`.
3. If a cross-cutting principle (applies to all of Maor's work) → most relevant `~/.claude/projects/.../memory/feedback_*.md` (or "create new feedback file" if none fits).
4. If project-specific (only this repo) → that repo's `CLAUDE.md`.
5. If unsure → pass the orchestrator file as candidate; the extractor will override if needed.

**Journal lifecycle for one user-correction event.**
1. Before spawning: append `status: raw, extractor_run: null`.
2. After extractor returns:
   - On `nothing-learnable` → append `status: nothing-learnable` (terminal). No surface.
   - On `Proposal` / `Proposal (replace)` / `Recommendation` → append `status: proposed` with the full extractor_run object.
3. In mode 1, surface the proposal immediately (see "Surface format" below). In mode 2, queue and continue.
4. On user approval (Proposal/Proposal-replace only): apply the Edit, append `status: approved` with `applied_commit: <sha or null>`. The orchestrator does NOT auto-commit lesson edits in v1.
5. On user rejection: append `status: rejected`.
6. On Recommendation approval: there's nothing to apply automatically. Append `status: approved` with `applied_commit: null`. The user implements the recommendation manually.
````

### C3: Source 2 — agent-self-report sub-section

Implementer in plan Task C3: append immediately after the C2 block, still inside `## Self-Learning Loop`.

````
### Source 2: agent-self-report

**Trigger.** After every main-agent return (developer, tester, QA, bug-fixer, architect, designer, integrator, planner, plan-challenger, researcher, jira-creator, conflict-resolver, jira-reader), scan the agent's return text for the literal header `^## Lessons` (case-sensitive, line-anchored).

If absent → no lesson event for this return. Continue normal phase routing.

If present → parse each `### Lesson` block under the `## Lessons` header. Each block has 4 fields:
```
### Lesson
Trigger: <text>
Generalizable rule: <text>
Suggested fix type: <one of the taxonomy values>
Suggested target: <file path or artifact>
```

Skip blocks missing any of the 4 fields (log a warning to the user: *"Agent <name> returned malformed Lesson block — skipping."*).

**For each well-formed `### Lesson` block:**

1. Apply near-duplicate suppression (same as user-correction): scan journal for prior `source: agent-self-report`, similar evidence, `status: rejected`, within last 50 events. If hit, append `suppressed-duplicate-rejection`, surface one-line note, skip.
2. Append `status: raw, extractor_run: null` to the journal.
3. Spawn `sdlc-lesson-extractor` with:
   ```
   Source: agent-self-report
   Evidence: <verbatim ### Lesson block>
   Context: agent=<agent name>, story=<story key>, epic=<epic key>, phase=<phase name>
   Target candidate: <agent's "Suggested target" value — extractor may override>
   Journal Path: ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
   ```
4. Same lifecycle as user-correction: extractor returns → append `proposed` (or `nothing-learnable`) → surface in mode 1 / queue in mode 2 → on approval append `approved` (with `applied_commit` for text edits, `null` for recommendations).

**Multiple lesson blocks per return.** Process each as a separate event. They may target different files; that's allowed (one file per *proposal*, but a single agent return can produce multiple proposals).

**Continue normal phase routing.** Self-learning runs alongside, never blocks. If any event is in mode 1 and you're awaiting approval, the surface is inline as part of the orchestrator turn — proceed to phase routing only after approval/rejection. In mode 2, phase routing continues immediately and proposals flush at the phase boundary.
````

### C4: Mode mechanics — surface, mode 2, proactive offer, persistence

Implementer in plan Task C4: append immediately after the C3 block.

````
### Surface format (mode 1, immediate)

When a proposal becomes ready, surface this to the user as a single message block:

```
📚 Lesson proposal — <Source> on <agent>/<story or epic>
Trigger: <trigger_summary>

<Verdict block as returned by the extractor — Proposal | Proposal (replace) | Recommendation>

Approve / Reject / Defer (mode 2 only)?
```

On user response:
- "approve" / "yes" / "apply" → Edit (for text-edit verdicts) or log-only (for Recommendation), append `status: approved`, brief one-line confirmation.
- "reject" / "no" / "skip" → append `status: rejected`, one-line confirmation.
- For mode-1, "defer" is not offered (it's a mode-2 concept).

Then continue with whatever phase work was in progress.

### Mode 2: batching at phase boundary

**Queue.** When mode is 2, every `proposed` event is added to an in-orchestrator-state queue (a list of event IDs). Do NOT surface to the user yet.

**Phase boundaries.** A flush happens at each natural pause point: end of Phase 1, 1.5, 2, 3, 3.5, 3.6, end-of-batch within Phase 4, end-of-story within Phases 5/6/7, end-of-merge-run in 7.5, and Phase 8. (These are points where the orchestrator was already going to update the user / pause for routing.)

**Flush procedure.** At each boundary, if the queue is non-empty:

1. Surface a single message:
   ```
   📚 <N> lesson proposals queued from <phase>:

   [1] <Source> • <target_file path basename> • <trigger_summary>
       <abbreviated verdict — first line of diff or recommendation type>
   [2] ...
   ...

   Approve all / Reject all / Defer all to next phase / Per-item (1: a/r/d, 2: a/r/d, ...)
   ```
2. On user response:
   - "approve all" → for each, apply (or log-only), append `status: approved`.
   - "reject all" → append `status: rejected` for each.
   - "defer all" → append `status: deferred` for each; re-queue at the start of the next phase.
   - Per-item like `1: a, 2: r, 3: d` → apply each verb to its event.
3. Empty the queue after applying.

**Mid-flush mode switch.** If the user says "mode 1" while a flush is in progress, finish the current flush first, then switch.

### Proactive mode-switch offer

In mode 1, track a counter `proposals_this_phase` (resets at every phase boundary).

When `proposals_this_phase` reaches 3 AND the user has not already declined an offer in this phase, BEFORE surfacing the next proposal:

```
📚 3 lesson proposals already this phase. Want to switch to mode 2 (batch at phase boundary) for this run? (yes / no / always mode 1)
```

- "yes" → switch to mode 2, queue the current pending proposal, continue.
- "no" → mark `offer_declined_this_phase = true`, surface the current proposal as normal.
- "always mode 1" → mark `offer_declined_session = true` (do not offer again until the user explicitly opts in).

Persist the decline flag in the auto-resume file under `## Mode` so it survives `/sdlc continue`.

### Switching modes on user request

Same LLM-intent classification approach as user-correction. After each user message, also classify:

> "Is this user message asking to change the lesson-proposal mode? Possible values: 'switch to mode 2' / 'switch to mode 1' / 'no'."

- `switch to mode 2` → confirm: *"Switching to mode 2 — proposals queue until phase boundary. Switch back with 'mode 1'."* Update state. Persist on next auto-save.
- `switch to mode 1` → confirm: *"Switching to mode 1 — proposals surface immediately."* Update state. Persist on next auto-save. If a queue exists, flush it now.
- `no` → continue.

### Persistence in the auto-resume file

In `Phase 0 → Auto-save` (and `Explicit handoff`), the orchestrator already writes a structured state file. Add a new block:

```
## Mode
current: 1 | 2
offer_declined_this_phase: true | false
offer_declined_session: true | false
proposals_this_phase: <integer>
queue: [<event_id>, ...]    # empty in mode 1; non-empty only in mode 2
```

On `Phase 0 → Fast Resume`, when reading the resume file, restore mode state from this block. If the block is absent, default to `current: 1, ...all flags false, proposals_this_phase: 0, queue: []`.
````

### C5: Self-Learning loop failures sub-section

Implementer in plan Task C5: append this block to the existing `## Error Handling` section, after its last existing bullet.

````
### Self-Learning loop failures

| Failure | Response |
|---|---|
| Extractor returns malformed output (no recognized verdict header) | Append `status: extraction-failed`, surface: *"Extractor returned malformed output for event <id> — skipping, see journal."* Continue. No auto-retry. |
| Extractor `Agent()` spawn returns a tool error | Retry once with a 2-second delay (Bash `sleep 2`). On second failure, treat as malformed (status `extraction-failed`). |
| Extractor times out (>3 minutes) | Treat as malformed. |
| Diff `old_string` doesn't match the canonical file (file changed since extractor read it) | Do NOT auto-rebase. Append `status: stale`. Surface to user with both the proposed diff and the current relevant region of the file. User decides: reject, or manually adapt and apply via Edit. |
| Edit succeeds but working tree was already dirty with unrelated changes | `applied_commit: null`. Do not auto-commit. User commits when ready (alongside their work). Provenance is via git blame after the eventual commit. |
| Journal write fails (disk/permission/IO) | Surface a hard error to the user: *"Journal write failed: <error>. Halting self-learning loop for this session. SDLC pipeline continues normally."* Mark `lesson_loop_disabled: true` in orchestrator state for this session. |
| Corrupt JSONL line in journal | Skip unparseable lines. Warn once per session: *"Skipped <N> unparseable lines in journal — see file for details."* Do not halt. |
| Mode-2 phase-boundary flush triggers but queue is unexpectedly empty | Log a warning, no halt. |
| Mode switch requested mid-flush | Finish current flush, then switch. |
| Correction-intent classified `no→yes` (false positive) | User rejects. Suppression remembers. Cost: one click. |
| Correction-intent classified `yes→no` (false negative) | Lesson missed. User repeats more emphatically next time; classification fires correctly. Cost: rare. |
| Correction-intent classified `yes→maybe` | One-line confirm. User answers. Cost: one round-trip. |
| Agent omits `## Lessons` despite friction | Not caught in v1. v2's transcript scan + hooks closes this gap. Acceptable known gap. |
| Agent over-reports (lesson for already-covered rule) | Extractor's existing-rule detection handles it (rewrite / recommend / move / nothing-learnable). Never silently discarded. |
| Agent suggests wrong target | Extractor's classification overrides. Suggestion is a hint, not authoritative. |
````

## Future work (v2)

Outline only.

- **Third source — hooks.** Tool-call instrumentation in `~/.claude/settings.json`. Emit structured events on retry-resolved patterns (e.g., 3rd Bash failure on same command → emit `retry-resolved` event). ≥2 repeats fires extractor with `Source: hook`.
- **Fourth source — transcript pattern-match.** Lightweight regex/LLM scan over the agent's transcript file after return. Catches retries the agent didn't self-report. Fires extractor only on extractor-confidence high.
- **Auto-proposers for non-text fix types.** Hook proposer: drafts a working `settings.json` snippet and validates it via dry-run before surfacing. Skill proposer: scaffolds the new skill file. Script proposer: writes the wrapper, sets executable bit, suggests PATH addition.
- **`/sdlc lessons` command family.** `review` (list recent), `revert {commit-sha}` (undo a lesson edit, mark journal `reverted`), `retry {id}` (re-run extractor on a specific event after fixing the underlying cause).
- **Cross-session repetition signal made explicit.** Currently in v1, repetition counting works across sessions because the journal is per-host-and-project, not per-session. Make this an explicit feature with stats (e.g., "this rule has been violated N times across M sessions over the last X days").
- **Auto-commit on clean tree.** When working tree is clean at the moment of Edit, auto-commit with a structured message linking to the journal event id. Today the user commits manually.
- **Fix-type effectiveness tracking.** When a lesson lands as instruction-edit, watch the journal: did the same friction recur within K events? If yes, the fix type was wrong → flip to enforcement recommendation automatically.
