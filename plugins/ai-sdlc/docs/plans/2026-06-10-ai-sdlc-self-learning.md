# AI-SDLC Self-Learning v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add in-flow lesson capture to the AI-SDLC pipeline. v1 sources: user corrections + agent self-reports. New `sdlc-lesson-extractor` sub-agent classifies fix type and proposes diffs (or recommends non-text fixes); orchestrator owns approval, edits, and journal writes.

**Architecture:** One new agent role file. The orchestrator command file (`commands/sdlc.md`) gains five integration blocks: correction-intent classification, return-scan for `## Lessons`, mode 1/2 state + switching, journal mechanics (append, repetition, near-duplicate suppression), and a phase-boundary flush hook. All 13 existing agent role files gain an identical `## Lessons` self-report block. Persistence: append-only JSONL at `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`, latest-line-per-id.

**Tech Stack:** Markdown plugin files (orchestrator command + agent role files). JSONL for the journal. No code in the conventional sense — the "implementation" is structured LLM instructions read by the runtime. Verification is via real `/sdlc` runs against scripted scenarios, not unit tests.

**Repo:** `~/git-dev/maor-skills-marketplace/`, branch `dev`. All edits target `plugins/ai-sdlc/`.

**Spec:** `plugins/ai-sdlc/docs/specs/2026-06-10-ai-sdlc-self-learning-design.md`

---

## How to verify markdown-instruction edits

This plan deviates from standard "write failing test → make it pass" because the artifact under test is LLM instructions, not code. Each task uses this verification shape instead:

- **Before-edit smoke probe** — describe the runtime behavior expected *before* the edit (so we can see the gap).
- **The edit** — exact text to add/change, with `old_string` and `new_string` shown verbatim.
- **After-edit smoke probe** — describe the behavior expected *after* the edit, and how to confirm.
- **Commit** — small, focused commits per task.

For probes that run a real `/sdlc` session, use a disposable epic. Detailed scenarios live in Phase D (smoke tests). Tasks A-C use lightweight probes (read the file back, verify presence of the new block; or trigger a single classification step).

---

## File Structure

**Files created (1):**
- `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md` — new agent role file

**Files modified (14):**
- `plugins/ai-sdlc/commands/sdlc.md` — orchestrator integration (5 blocks)
- `plugins/ai-sdlc/agents/sdlc-researcher.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-planner.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-plan-challenger.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-jira-creator.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-architect.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-designer.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-integrator.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-developer.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-tester.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-qa-reviewer.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-bug-fixer.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-conflict-resolver.md` — add `## Lessons` block
- `plugins/ai-sdlc/agents/sdlc-jira-reader.md` — add `## Lessons` block

**Files created at runtime (not by this plan):**
- `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl` — journal (created on first event by the orchestrator)

---

## Phase A — Foundations

Build the new agent file and the orchestrator's plumbing for lesson-extractor spawning, before touching any existing agent.

### Task A1: Create the `sdlc-lesson-extractor` agent file

**Files:**
- Create: `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`

- [ ] **Step 1: Read an existing agent file as the format reference**

Read: `plugins/ai-sdlc/agents/sdlc-jira-reader.md` (already short, 127 lines, uses sonnet, similar single-shot return pattern).

Confirm the structure: YAML frontmatter (`name`, `description`, `model`, `color`), then `## CRITICAL — Load MCP Tools First` (only if MCP needed — extractor does NOT need MCP), then role body.

- [ ] **Step 2: Write `sdlc-lesson-extractor.md`**

Create the file with this exact content:

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
2. **Parse the prompt.** It contains:
   - `Source`: `user-correction` | `agent-self-report`
   - `Evidence`: verbatim text — user message + recent actions, or the agent's `### Lesson` block
   - `Context`: agent name, story key, epic key, phase
   - `Target candidate`: orchestrator's best guess at the canonical file to edit
   - `Journal Path`: absolute path to `sdlc-events.jsonl`
3. **Classify fix type.** Decide which of these is the highest-leverage, lowest-risk fix:
   - `instruction-edit` — agent role file (`plugins/ai-sdlc/agents/sdlc-*.md`), orchestrator command file (`plugins/ai-sdlc/commands/sdlc.md`)
   - `memory-feedback` — `~/.claude/projects/.../memory/feedback_*.md` (cross-cutting principle)
   - `project-claudemd` — repo-local `CLAUDE.md` (project-specific rule)
   - `hook` — `~/.claude/settings.json` PreToolUse / PostToolUse hook
   - `skill` — new or existing skill file
   - `script` — shell wrapper (e.g., `uv-zs` that always sets `SSL_CERT_FILE`)
   - `slash-command` — new `/sdlc-X` style command
   - `manual` — none of the above; user must decide
4. **Read ONE candidate canonical file** (the one your fix targets, if it's `instruction-edit` / `memory-feedback` / `project-claudemd`). Skip this step for non-text fix types.
5. **Detect existing rule.** Scan the candidate file for related wording. If found, classify failure mode:
   - **wording** — existing rule is vague, hedged, buried, or contradicted by another rule. Fix: rewrite.
   - **repetition** — existing rule is fine but agents keep violating it. Read the journal: count prior events with same `target_file` and overlapping `existing_rule.location` (same line ±5 or same section header), status in `{approved, proposed, raw}`, latest line per id. If count ≥2 → repetition.
   - **scope** — rule is in the wrong file/section.
6. **Draft the verdict and output.**

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

- [ ] **Step 3: Verify the file is well-formed**

Run: `head -25 plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`
Expected: YAML frontmatter visible, `name: sdlc-lesson-extractor`, `model: sonnet`.

Run: `wc -l plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`
Expected: roughly 130-180 lines.

- [ ] **Step 4: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/agents/sdlc-lesson-extractor.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add sdlc-lesson-extractor agent for self-learning v1"
```

---

### Task A2: Add the lesson-extractor to the orchestrator's `Agent Paths` map

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (Phase 0 step 4b — `Agent Paths` block)

- [ ] **Step 1: Locate the `Agent Paths` map in the orchestrator**

Run: `grep -n "Agent Paths" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`

Confirm it lists 13 roles: researcher, planner, plan-challenger, jira-creator, architect, designer, integrator, developer, tester, qa-reviewer, bug-fixer, conflict-resolver, reader.

- [ ] **Step 2: Read the surrounding section**

Read `plugins/ai-sdlc/commands/sdlc.md` around the `Agent Paths` block (Phase 0, step 4b — roughly lines 280-340).

- [ ] **Step 3: Add `lesson-extractor` to the map**

Edit `plugins/ai-sdlc/commands/sdlc.md`. Find the `Agent Paths` block and add a new entry:

```
old_string: |
       reader:            "/.../plugins/ai-sdlc/agents/sdlc-jira-reader.md",
     }
new_string: |
       reader:            "/.../plugins/ai-sdlc/agents/sdlc-jira-reader.md",
       lesson-extractor:  "/.../plugins/ai-sdlc/agents/sdlc-lesson-extractor.md",
     }
```

- [ ] **Step 4: Add the lesson-extractor to the model table**

Find the model-per-role table (also in the "How to Spawn Agents" section). Add a row:

```
old_string: |
   | sdlc-jira-reader | sonnet |
new_string: |
   | sdlc-jira-reader | sonnet |
   | sdlc-lesson-extractor | sonnet |
```

- [ ] **Step 5: Verify**

Run: `grep -n "lesson-extractor" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: at least 2 hits (Agent Paths entry + model table entry).

- [ ] **Step 6: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): register sdlc-lesson-extractor in Agent Paths and model table"
```

---

## Phase B — Agent self-report contract

Add the same `## Lessons` block to all 13 existing agent role files. Mechanical, repetitive — but each one is a separate task so commits are clean and any failure is isolated.

### The exact block to add (used in B1-B13)

This is appended near the end of each agent's role body, AFTER the existing "Output Rules" / output section, BEFORE any final examples block (or at end of file if no examples block):

```markdown
## Lessons (optional, append at end of return text)

If during your run you:
- Retried a tool/command after a failure and the second-or-later attempt succeeded
- Worked around a non-obvious problem (missing env var, wrong path, contract mismatch with an artifact you read)
- Discovered something that contradicts your role definition or an artifact you read
- Found that a sibling artifact (tech spec, design spec, integration notes) was wrong or incomplete

…then append a `## Lessons` section to your final return text. Each lesson is one block:

```
### Lesson
Trigger: <one sentence — what happened>
Generalizable rule: <one sentence — phrased imperatively, what should always/never happen>
Suggested fix type: <instruction-edit | memory-feedback | hook | skill | script | slash-command | manual>
Suggested target: <file path or artifact, your best guess — extractor may override>
```

If your run had no friction worth a lesson, omit the section entirely. Do NOT include lessons for things that are already covered by your role definition.
```

(Note the inner code fence is plain ``` — no language tag — to avoid markdown nesting issues. The outer block in this plan uses regular markdown so the actual file content is the inner block plus the surrounding prose.)

---

### Task B1: Add `## Lessons` block to `sdlc-developer.md`

**Files:**
- Modify: `plugins/ai-sdlc/agents/sdlc-developer.md`

- [ ] **Step 1: Read the file to find the right insertion point**

Read `plugins/ai-sdlc/agents/sdlc-developer.md`. Identify the last section before any examples or end-of-file. The block goes immediately after the existing "Output Rules" / final-output guidance.

- [ ] **Step 2: Apply the edit**

Use the `## Lessons` block exactly as defined above. Pick `old_string` as the last existing line of the prior section and `new_string` as that line plus a blank line plus the full `## Lessons` block.

Concrete pattern:
```
old_string: |
  <last line of preceding section, verbatim>
new_string: |
  <last line of preceding section, verbatim>

  ## Lessons (optional, append at end of return text)
  ... (full block)
```

- [ ] **Step 3: Verify presence**

Run: `grep -n "^## Lessons" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/agents/sdlc-developer.md`
Expected: one hit.

- [ ] **Step 4: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/agents/sdlc-developer.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add Lessons self-report block to sdlc-developer"
```

---

### Tasks B2-B13: Repeat for the other 12 agent files

Same procedure as B1, one task each, in this order:

- [ ] **B2:** `sdlc-architect.md`
- [ ] **B3:** `sdlc-tester.md`
- [ ] **B4:** `sdlc-qa-reviewer.md`
- [ ] **B5:** `sdlc-bug-fixer.md`
- [ ] **B6:** `sdlc-designer.md`
- [ ] **B7:** `sdlc-integrator.md`
- [ ] **B8:** `sdlc-conflict-resolver.md`
- [ ] **B9:** `sdlc-planner.md`
- [ ] **B10:** `sdlc-plan-challenger.md`
- [ ] **B11:** `sdlc-researcher.md`
- [ ] **B12:** `sdlc-jira-creator.md`
- [ ] **B13:** `sdlc-jira-reader.md`

For each: read the file → identify the last section before end-of-file → apply the same `## Lessons` block in the same way → verify with `grep -n "^## Lessons"` → commit with `feat(ai-sdlc): add Lessons self-report block to <agent-name>`.

After B13, run a sweep to confirm all 13 files have the block:

```bash
for f in ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/agents/sdlc-*.md; do
  grep -L "^## Lessons" "$f" && echo "MISSING in $f"
done
```

Expected: no output (all files contain the block). The new `sdlc-lesson-extractor.md` does NOT need this block (it's the extractor itself, not a normal SDLC agent). Confirm by checking that file is not in the loop output above — if `grep -L` flags it, that's expected and fine; just don't add the block to it.

Adjust the loop to exclude the extractor:
```bash
for f in ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/agents/sdlc-*.md; do
  case "$f" in *sdlc-lesson-extractor.md) continue ;; esac
  grep -L "^## Lessons" "$f" && echo "MISSING in $f"
done
```

---

## Phase C — Orchestrator integration

Five additions to `plugins/ai-sdlc/commands/sdlc.md`. Each task ends in a commit so any single addition can be reverted cleanly.

### Task C1: Add the "Self-Learning" section header and overview to the orchestrator

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (insert before `## Error Handling`, near the bottom)

The orchestrator command file is large and dense. Rather than scattering self-learning logic through existing phases, add one consolidated `## Self-Learning Loop` section near the bottom (before `## Error Handling`), which subsequent tasks fill in. Then add explicit pointers from existing phases (Phase 0, the spawn pattern, return-handling) into this section.

- [ ] **Step 1: Locate insertion point**

Run: `grep -n "^## Error Handling" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one match around line 832.

- [ ] **Step 2: Insert section header and overview**

Edit `plugins/ai-sdlc/commands/sdlc.md`. Insert immediately before `## Error Handling`:

```
old_string: |
  ## Error Handling
new_string: |
  ## Self-Learning Loop

  The orchestrator captures lessons in-flow from two sources (v1): user corrections and agent `## Lessons` self-reports. Each event spawns the `sdlc-lesson-extractor` sub-agent, which classifies fix type and returns a structured verdict. Approved text-edit verdicts apply directly to canonical files; non-text verdicts (hook / script / skill / slash-command) surface as recommendations the user implements manually.

  See `docs/specs/2026-06-10-ai-sdlc-self-learning-design.md` for the full design.

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

  ## Error Handling
```

- [ ] **Step 3: Verify**

Run: `grep -n "^## Self-Learning Loop" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

- [ ] **Step 4: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add Self-Learning Loop section header to orchestrator"
```

---

### Task C2: Add the correction-intent classification rule

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (extend `## Self-Learning Loop` with classification rule + spawn instructions)

- [ ] **Step 1: Append the user-correction sub-section**

Edit `plugins/ai-sdlc/commands/sdlc.md`. Find the `### Journal` block from C1 and add immediately after it:

```
old_string: |
  Bootstrap: the journal file is created on the first event (Bash: `mkdir -p $(dirname <journal>) && touch <journal>` if absent). Never fail the SDLC pipeline because the journal can't be written; if writes fail (disk/permission), surface a hard error and halt the lesson loop for the session, but continue the SDLC pipeline.

  ## Error Handling
new_string: |
  Bootstrap: the journal file is created on the first event (Bash: `mkdir -p $(dirname <journal>) && touch <journal>` if absent). Never fail the SDLC pipeline because the journal can't be written; if writes fail (disk/permission), surface a hard error and halt the lesson loop for the session, but continue the SDLC pipeline.

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

  ## Error Handling
```

- [ ] **Step 2: Verify**

Run: `grep -n "^### Source 1: user-correction" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

- [ ] **Step 3: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add user-correction detection and routing to self-learning loop"
```

---

### Task C3: Add the agent self-report scan rule

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (extend `## Self-Learning Loop` with self-report rule)

- [ ] **Step 1: Append the self-report sub-section**

Edit `plugins/ai-sdlc/commands/sdlc.md`. Find the end of the `### Source 1: user-correction` block and add immediately after:

```
old_string: |
  6. On Recommendation approval: there's nothing to apply automatically. Append `status: approved` with `applied_commit: null`. The user implements the recommendation manually.

  ## Error Handling
new_string: |
  6. On Recommendation approval: there's nothing to apply automatically. Append `status: approved` with `applied_commit: null`. The user implements the recommendation manually.

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

  ## Error Handling
```

- [ ] **Step 2: Verify**

Run: `grep -n "^### Source 2: agent-self-report" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

- [ ] **Step 3: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add agent self-report scan to self-learning loop"
```

---

### Task C4: Add mode 2 batching + phase-boundary flush + proactive offer

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (extend `## Self-Learning Loop` with mode mechanics)

- [ ] **Step 1: Append the mode-mechanics sub-section**

Edit `plugins/ai-sdlc/commands/sdlc.md`. Find the end of the `### Source 2: agent-self-report` block and add immediately after:

```
old_string: |
  **Continue normal phase routing.** Self-learning runs alongside, never blocks. If any event is in mode 1 and you're awaiting approval, the surface is inline as part of the orchestrator turn — proceed to phase routing only after approval/rejection. In mode 2, phase routing continues immediately and proposals flush at the phase boundary.

  ## Error Handling
new_string: |
  **Continue normal phase routing.** Self-learning runs alongside, never blocks. If any event is in mode 1 and you're awaiting approval, the surface is inline as part of the orchestrator turn — proceed to phase routing only after approval/rejection. In mode 2, phase routing continues immediately and proposals flush at the phase boundary.

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

  ## Error Handling
```

- [ ] **Step 2: Verify**

Run: `grep -n "^### Mode 2:" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

Run: `grep -n "^### Proactive mode-switch offer" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

- [ ] **Step 3: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add mode 2 batching, phase-boundary flush, proactive offer"
```

---

### Task C5: Add error-handling rules for the self-learning loop

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (extend the existing `## Error Handling` section)

The orchestrator already has an `## Error Handling` section (around line 832). Add a new sub-section for self-learning failure modes.

- [ ] **Step 1: Locate the existing `## Error Handling` section**

Run: `grep -n "^## Error Handling" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`

Read 30 lines starting at that line number to see what's already there.

- [ ] **Step 2: Append self-learning error rules**

Find the last bullet in `## Error Handling` and add the self-learning sub-section after it:

```
old_string: |
  - **Missing workflow status:** Fall back to To Do / In Progress / Done. Use comments for sub-states.
new_string: |
  - **Missing workflow status:** Fall back to To Do / In Progress / Done. Use comments for sub-states.

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
```

- [ ] **Step 3: Verify**

Run: `grep -n "^### Self-Learning loop failures" ~/git-dev/maor-skills-marketplace/plugins/ai-sdlc/commands/sdlc.md`
Expected: one hit.

- [ ] **Step 4: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): add error-handling rules for self-learning loop"
```

---

## Phase D — Smoke verification

10 scenarios from the spec. These run as actual `/sdlc` sessions in a controlled scratch context. Each task = one scenario, with a clean journal state and observable outcome.

**Setup before D1:** create a sandbox directory for journal experiments so the production journal isn't affected by smoke runs.

### Task D0: Set up smoke test sandbox

**Files:**
- Create: `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.smoke.jsonl` (empty)
- Modify: nothing yet

- [ ] **Step 1: Create the sandbox journal**

Run:
```bash
mkdir -p ~/.claude/projects/-Users-maorb-git-dev/memory
: > ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.smoke.jsonl
```

Expected: file exists, size 0.

Run: `ls -la ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.smoke.jsonl`
Expected: file present, 0 bytes.

- [ ] **Step 2: Plan how each scenario uses the sandbox**

Each smoke scenario below uses the **production journal path** in its prompt (since the orchestrator file hardcodes that path), but BEFORE running the scenario, back up the production journal:

```bash
JOURNAL=~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
[ -f "$JOURNAL" ] && cp "$JOURNAL" "$JOURNAL.bak.$(date +%Y%m%d-%H%M%S)"
: > "$JOURNAL"   # truncate for clean state
```

After each scenario, restore from the most recent backup OR keep the smoke entries (they're real lessons; nothing to revert if you accept what was proposed).

Document this protocol once at the top of D1's first step so the actual scenarios can be terse.

No commit needed for D0.

---

### Task D1: Smoke test 1 — User-correction → instruction edit (happy path)

**Goal:** Verify that a clear user correction triggers classification → extractor → proposal → approval → Edit → journal append.

- [ ] **Step 1: Reset journal**

```bash
JOURNAL=~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
[ -f "$JOURNAL" ] && cp "$JOURNAL" "$JOURNAL.bak.$(date +%Y%m%d-%H%M%S)"
: > "$JOURNAL"
```

- [ ] **Step 2: Reload the plugin in a fresh Claude Code session**

In the test session, run `/reload-plugins` to pick up the new `sdlc-lesson-extractor` agent and the orchestrator changes.

- [ ] **Step 3: Trigger a real (small) `/sdlc` run**

Use a tiny scratch task. Recommended: a one-story "hello world" feedback-loop run on an existing test project. Anything that makes the orchestrator do *some* observable action and then accept a correction.

- [ ] **Step 4: Send a clear correction message**

Mid-run, send:
> "from now on, always commit with a Co-Authored-By footer for ai-sdlc commits"

- [ ] **Step 5: Verify behavior**

Expected sequence in the orchestrator's response:
1. Classifies the message as `yes` (user-correction).
2. Spawns `sdlc-lesson-extractor` (visible as a tool call).
3. Surfaces a proposal with `## Proposal` block, target file, trigger summary, and a diff.
4. Waits for approval.

If the classifier returns `no` or `maybe`: that's a v1 false-negative. Document it as a smoke failure and refine the prompt in C2's classification rule before re-running.

- [ ] **Step 6: Approve the proposal**

Reply: "approve"

Expected: orchestrator runs Edit on the canonical file, surfaces a one-line confirmation ("Lesson applied to <file>."), and appends an `approved` line to the journal.

- [ ] **Step 7: Verify journal state**

```bash
wc -l ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
```
Expected: at least 3 lines (raw → proposed → approved).

```bash
tail -1 ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl | jq '.status'
```
Expected: `"approved"`.

- [ ] **Step 8: Verify file change**

```bash
git -C ~/git-dev/maor-skills-marketplace diff <target_file>
```
Expected: a small additive diff matching the proposal.

- [ ] **Step 9: Restore (or keep) the change**

If the proposed edit is keepable, commit it with the `applied_commit` flow. If not, `git -C ~/git-dev/maor-skills-marketplace checkout -- <file>`.

- [ ] **Step 10: Note pass/fail in scratch**

If pass: proceed to D2. If fail: file the gap and return to the relevant Phase C task.

No code commit for D1 (it's a runtime test).

---

### Tasks D2-D10: remaining smoke scenarios

Each follows the same shape as D1 (reset journal → trigger scenario → verify behavior → verify journal → notes). Brief specifications below; expand the steps in the same shape as D1 when executing.

- [ ] **D2: Self-report → extractor.** Trigger an SDLC story end-to-end with a deliberately-failing test (or env mismatch) that forces an agent to retry. Expect the agent's return text to contain `## Lessons`. Verify orchestrator parses, spawns, surfaces, applies on approval. Pass: journal contains `proposed → approved` for `source: agent-self-report`.

- [ ] **D3: Existing-rule, cause = wording.** Plant a vague rule in `sdlc-developer.md` (e.g., "Prefer git -C when convenient"). Reset journal. Trigger correction "always use git -C, never cd && git". Pass: extractor returns `Proposal (replace)`, surface includes `## Existing Rule` block naming the line being replaced, diff is the rewrite (not a new line append).

- [ ] **D4: Existing-rule, cause = repetition.** Manually pre-seed the journal with two `approved` events targeting the same rule (same `target_file` and `existing_rule.location` ±5 lines). Reset NOT applicable (the seeds are the test). Trigger a third user-correction on the same topic. Pass: extractor returns `Recommendation` with hook/script suggestion, journal entry has `fix_type: "hook"` (or similar enforcement type), no Edit applied.

- [ ] **D5: Maybe-classification → confirm gate.** Send a deliberately ambiguous message: "this seems off". Pass: orchestrator asks the one-line confirm question. Test both branches: yes → spawn fires; no → no journal entry, no spawn.

- [ ] **D6: Mode 2 batching.** Switch to mode 2 with "switch to mode 2". Trigger 3 events in one phase (mix of user-correction and a synthetic agent self-report). Pass: orchestrator does NOT surface proposals as they happen; at end of phase, all 3 surface in one batch with bulk options.

- [ ] **D7: Proactive mode-switch offer.** Stay in mode 1. Fire 3 proposals in one phase (synthetic — could be 3 corrections in a row). Pass: before the would-be 4th proposal, orchestrator offers the switch. Test both branches: yes → mode flips, queue forms; no → next proposal surfaces normally; "always mode 1" → no further offers in this session.

- [ ] **D8: Near-duplicate suppression.** Reject a proposal in D1 first (re-run D1, but reject instead of approve). Then send the same correction message again. Pass: orchestrator detects, appends `suppressed-duplicate-rejection`, surfaces one-line note, does NOT spawn the extractor (verify by absence of a Tool call to `sdlc-lesson-extractor`).

- [ ] **D9: Stale diff handling.** Trigger an event. Before approving, in another terminal, manually edit the target file so the proposed `old_string` no longer matches. Approve. Pass: orchestrator's Edit attempt fails, appends `status: stale`, surface shows current file content for the region, no Edit applied.

- [ ] **D10: Journal corruption resilience.** Corrupt one line of the journal:
  ```bash
  echo "this is not json" >> ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
  ```
  Trigger an event that reads the journal (D8's near-duplicate scan needs a journal read). Pass: orchestrator surfaces a one-time warning ("Skipped 1 unparseable line"), continues normally, completes the scan. No halt.

After D10: all smoke tests pass → v1 is shippable. Any failures: triage and patch the relevant Phase C task; do not move to v2.

---

## Phase E — Promote to main

Once D1-D10 pass on `dev`:

### Task E1: Final dev-branch commit + push

- [ ] **Step 1: Verify clean dev branch**

```bash
git -C ~/git-dev/maor-skills-marketplace status
```
Expected: clean tree (or only the smoke-run artifacts you intentionally kept).

- [ ] **Step 2: Push dev**

```bash
git -C ~/git-dev/maor-skills-marketplace push origin dev
```

- [ ] **Step 3: Notify the user**

Per the user's standing preference (memory: "Don't prompt for promotion"), do NOT ask to merge to main. The user will request promotion when ready. Just confirm: "v1 self-learning is on `dev`. Smoke tests passed. Ready for promotion when you say so."

---

## Spec coverage check (self-review)

Cross-referencing every section of the spec against the tasks:

| Spec section | Covered by |
|---|---|
| Architecture diagram | A1 (extractor agent) + C1-C5 (orchestrator integration) |
| `sdlc-lesson-extractor` agent contract | A1 |
| Inputs / verdicts / constraints | A1 |
| Source 1: user-correction (LLM intent classification, maybe-confirm gate) | C2 |
| Source 2: agent self-report (`## Lessons` block, parse rules) | B1-B13 (block in agents) + C3 (orchestrator scan) |
| Source-weighted bar (always propose for v1 sources) | C2, C3 (no thresholds applied for these sources) |
| Existing-rule detection (wording / repetition / scope causes) | A1 (extractor process step 5 + repetition algorithm) |
| Verdict outputs (Proposal / replace / Recommendation / nothing-learnable) | A1 |
| Mode 1 (immediate) | C2 lifecycle step 3 + C4 surface format |
| Mode 2 (batch) + phase-boundary flush | C4 |
| Switching modes (LLM intent + proactive offer at ≥3) | C4 |
| Mid-flush switch handling | C4 |
| Persistence: JSONL schema + lifecycle | C1 (overview) + C2 (lifecycle) + C3 (lifecycle) |
| Logical updates via re-appended lines | C1 |
| Repetition detection algorithm | A1 |
| Near-duplicate suppression | C2, C3 |
| Hygiene (no auto-rotation, manual archive) | C1 |
| Error handling (all 14 rows in spec table) | C5 |
| Smoke tests 1-10 | D1-D10 |
| v2 future work (hooks, transcript scan, /sdlc lessons commands) | Out of scope; design spec retains the outline |

**Gaps found and addressed inline:**
- The spec mentions persisting mode state in the auto-resume file but doesn't specify the format. Plan task C4 specifies the `## Mode` block format explicitly.
- The spec doesn't specify the journal bootstrap (creation on first event). Plan task C1 covers it.
- The spec doesn't specify how multi-block `## Lessons` returns are handled. Plan task C3 specifies "process each as a separate event."

**Placeholder scan:** No "TBD", "TODO", or "implement later" anywhere. Code blocks present where needed (the agent role file body, journal schema, surface formats, exact diffs for the orchestrator inserts).

**Type/name consistency:** Verdict names match across A1 and C2/C3 (`Proposal`, `Proposal (replace)`, `Recommendation`, `nothing learnable`). Status enum matches across C1, C2, C3, C5. Field names (`extractor_run`, `existing_rule`, `applied_commit`, `suggested_artifact`) match the spec's schema.

