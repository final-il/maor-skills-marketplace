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

## Future work (v2)

Outline only.

- **Third source — hooks.** Tool-call instrumentation in `~/.claude/settings.json`. Emit structured events on retry-resolved patterns (e.g., 3rd Bash failure on same command → emit `retry-resolved` event). ≥2 repeats fires extractor with `Source: hook`.
- **Fourth source — transcript pattern-match.** Lightweight regex/LLM scan over the agent's transcript file after return. Catches retries the agent didn't self-report. Fires extractor only on extractor-confidence high.
- **Auto-proposers for non-text fix types.** Hook proposer: drafts a working `settings.json` snippet and validates it via dry-run before surfacing. Skill proposer: scaffolds the new skill file. Script proposer: writes the wrapper, sets executable bit, suggests PATH addition.
- **`/sdlc lessons` command family.** `review` (list recent), `revert {commit-sha}` (undo a lesson edit, mark journal `reverted`), `retry {id}` (re-run extractor on a specific event after fixing the underlying cause).
- **Cross-session repetition signal made explicit.** Currently in v1, repetition counting works across sessions because the journal is per-host-and-project, not per-session. Make this an explicit feature with stats (e.g., "this rule has been violated N times across M sessions over the last X days").
- **Auto-commit on clean tree.** When working tree is clean at the moment of Edit, auto-commit with a structured message linking to the journal event id. Today the user commits manually.
- **Fix-type effectiveness tracking.** When a lesson lands as instruction-edit, watch the journal: did the same friction recur within K events? If yes, the fix type was wrong → flip to enforcement recommendation automatically.
