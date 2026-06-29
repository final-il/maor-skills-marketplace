# AI-SDLC Self-Learning v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **2026-06-29 reconciliation.** Capture is **hook-based and v1** (not v2, not orchestrator-attention-based). Two Claude Code hooks under `plugins/ai-sdlc/hooks/` perform deterministic capture: the **SubagentStop hook** (`capture-subagent-lessons.sh`, CSI-638 — landed) captures agent `## Lessons` self-reports by reconstructing the agent's final text from `transcript_path`; the **UserPromptSubmit hook** (CSI-639) captures user corrections via keyword pre-filter → Haiku classifier. Both append `status:"raw"` events. The orchestrator's job is to **drain the raw queue** (CSI-640) and spawn the extractor per event — it no longer classifies corrections or scans returns itself. Tasks C2/C3 below are superseded by the hooks + drain step; they remain documented for the lifecycle they describe but the *detection* they specify now lives in the hooks. See the design spec's Architecture and Hook-contracts sections.

**Goal:** Add in-flow lesson capture to the AI-SDLC pipeline. v1 sources: user corrections + agent self-reports, both **captured deterministically by hooks**. New `sdlc-lesson-extractor` sub-agent classifies fix type and proposes diffs (or recommends non-text fixes); orchestrator owns the drain step, approval, edits, and journal lifecycle writes.

**Architecture:** Two capture hooks + one new agent role file. The hooks (`plugins/ai-sdlc/hooks/`) capture both v1 sources deterministically and append `status:"raw"` events. The orchestrator command file (`commands/sdlc.md`) gains: a *drain-the-raw-queue* step (CSI-640), mode 1/2 state + switching, journal lifecycle mechanics (append non-raw transitions, repetition, near-duplicate suppression), and a phase-boundary flush. (Detection — correction-intent classification and the `## Lessons` return-scan — now lives in the hooks, not the orchestrator.) All 13 existing agent role files gain an identical `## Lessons` self-report block. Persistence: append-only JSONL at `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl`, latest-line-per-id.

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

**Files created (1 agent + hooks):**
- `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md` — new agent role file
- `plugins/ai-sdlc/hooks/hooks.json` — hook registration (SubagentStop + UserPromptSubmit)
- `plugins/ai-sdlc/hooks/capture-subagent-lessons.sh` — SubagentStop capture hook (CSI-638, landed)
- `plugins/ai-sdlc/hooks/lib/journal-append.sh` — shared journal helpers (path, toggle, event-id, append)
- `plugins/ai-sdlc/hooks/` UserPromptSubmit capture hook — user-correction capture (CSI-639)

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

### Task A0: Toggle plumbing — resume-file field and SDLC Context line

This task lays the deterministic on/off rails the rest of the plan depends on. After A0, every subsequent task can rely on `Self-Learning: ON|OFF` being present in every spawned agent's prompt.

**Files:**
- Modify: `plugins/ai-sdlc/commands/sdlc.md` (auto-resume save block + SDLC Context block template)

- [ ] **Step 1: Locate the auto-resume save section in `commands/sdlc.md`**

Run: `grep -n "## Mode\|sdlc-resume-\|auto-resume" plugins/ai-sdlc/commands/sdlc.md`

Expected: a section that documents the resume file's structure, including a `## Mode` field. The new `## Self-Learning` field goes adjacent.

- [ ] **Step 2: Add `## Self-Learning` to the auto-resume file template**

In the resume-file template within `commands/sdlc.md`, add this block right after `## Mode`:

```markdown
## Self-Learning
enabled: true
```

Document in the orchestrator: "Default `true` if the field or file is missing. Persisted on every auto-save. Read on Phase 0 fast resume; restores in-memory toggle state."

- [ ] **Step 3: Locate the SDLC Context block template**

Run: `grep -n "SDLC Context\|Transition Map\|Agent Paths" plugins/ai-sdlc/commands/sdlc.md`

Expected: the template enumerating the lines passed to every agent spawn (Project Name, Transition Map, Agent Paths, Worktree Path, etc.).

- [ ] **Step 4: Add `Self-Learning: ON|OFF` to the SDLC Context block**

Add a new line in the template, near `Mode:` (or near the end of the deterministic-state lines):

```
Self-Learning: ON
```

Document: "Built from the in-memory toggle state, which is restored from the resume file's `## Self-Learning` field on Phase 0. Default ON. Every agent spawn includes this line verbatim."

- [ ] **Step 5: Add toggle-state initialization rule for new sessions**

Document somewhere readable from Phase 0: "If the resume file has no `## Self-Learning` field, treat the toggle as ON. On first auto-save, write `enabled: true` so subsequent reads are explicit."

- [ ] **Step 6: Smoke probe — read the file back**

Run: `grep -A2 "## Self-Learning" plugins/ai-sdlc/commands/sdlc.md`

Expected: the new template block visible in `commands/sdlc.md`.

Run: `grep "Self-Learning: ON" plugins/ai-sdlc/commands/sdlc.md`

Expected: the new context-block line visible.

- [ ] **Step 7: Commit**

```bash
git -C ~/git-dev/maor-skills-marketplace add plugins/ai-sdlc/commands/sdlc.md
git -C ~/git-dev/maor-skills-marketplace commit -m "feat(ai-sdlc): self-learning toggle plumbing (state + context line)"
```

### Task A1: Create the `sdlc-lesson-extractor` agent file

**Files:**
- Create: `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`

- [ ] **Step 1: Read an existing agent file as the format reference**

Read: `plugins/ai-sdlc/agents/sdlc-jira-reader.md` (already short, 127 lines, uses sonnet, similar single-shot return pattern).

Confirm the structure: YAML frontmatter (`name`, `description`, `model`, `color`), then `## CRITICAL — Load MCP Tools First` (only if MCP needed — extractor does NOT need MCP), then role body.

- [ ] **Step 2: Write `sdlc-lesson-extractor.md` from the spec**

The full file body lives in the spec, section **"Canonical content for plan tasks → A1: Full body of `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`"** (`docs/specs/2026-06-10-ai-sdlc-self-learning-design.md`).

Open that section. Copy everything inside the outer ` ```` `markdown fence — frontmatter (`---` to `---`) plus body. Do not edit while pasting; the toggle gate at Process step 2 must remain. Write the result to `plugins/ai-sdlc/agents/sdlc-lesson-extractor.md`.

If the spec changes after you read it, re-read it and re-paste — the spec is canonical.

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

**Self-learning toggle gate.** Read your prompt's SDLC Context block. If the line `Self-Learning: OFF` is present, **omit this entire `## Lessons` section** from your return text — do not emit any `### Lesson` block regardless of in-flow friction. Only emit lessons when `Self-Learning: ON` (or when no `Self-Learning` line is present, which means the orchestrator is pre-toggle and self-learning is implicitly on).

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

If your run had no friction worth a lesson, omit the section entirely. If something IS covered by your role definition but still caused friction — that's a red flag worth reporting (the definition may be unclear, outdated, or not being followed).
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

Edit `plugins/ai-sdlc/commands/sdlc.md`. Insert immediately before `## Error Handling` the canonical content from the spec, section **"Canonical content for plan tasks → C1: Self-Learning Loop section header"** (`docs/specs/2026-06-10-ai-sdlc-self-learning-design.md`).

The Edit shape:
- `old_string`: the existing line `## Error Handling`.
- `new_string`: the full C1 block from the spec (verbatim — Self-Learning Loop overview + Toggle + Mode + Journal sub-sections), followed by a blank line and then `## Error Handling`.

The new section header must appear immediately before `## Error Handling` in the file.

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

Edit `plugins/ai-sdlc/commands/sdlc.md`. Insert the canonical content from spec section **"Canonical content for plan tasks → C2: Source 1 — user-correction sub-section"** immediately after the C1 block's `### Journal` content, still inside the `## Self-Learning Loop` section (i.e., before `## Error Handling`).

The Edit shape:
- `old_string`: the last paragraph of the C1 `### Journal` block (ending with "...continue the SDLC pipeline.") followed by a blank line and `## Error Handling`.
- `new_string`: same closing-of-Journal text + the full C2 spec block + a blank line + `## Error Handling`.

This preserves C1's last paragraph and inserts C2 between Journal and Error Handling.

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

Edit `plugins/ai-sdlc/commands/sdlc.md`. Insert the canonical content from spec section **"Canonical content for plan tasks → C3: Source 2 — agent-self-report sub-section"** immediately after the C2 block's `### Source 1` content, still inside the `## Self-Learning Loop` section (i.e., before `## Error Handling`).

The Edit shape:
- `old_string`: the last line of the C2 `### Source 1` block (ending with "...The user implements the recommendation manually.") followed by a blank line and `## Error Handling`.
- `new_string`: same closing-of-Source-1 line + the full C3 spec block + a blank line + `## Error Handling`.

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

Edit `plugins/ai-sdlc/commands/sdlc.md`. Insert the canonical content from spec section **"Canonical content for plan tasks → C4: Mode mechanics — surface, mode 2, proactive offer, persistence"** immediately after the C3 block's `### Source 2` content, still inside the `## Self-Learning Loop` section (i.e., before `## Error Handling`).

The Edit shape:
- `old_string`: the last paragraph of the C3 `### Source 2` block (the "Continue normal phase routing." paragraph) followed by a blank line and `## Error Handling`.
- `new_string`: same closing-of-Source-2 paragraph + the full C4 spec block (Surface format / Mode 2 / Proactive offer / Switching / Persistence sub-sections) + a blank line + `## Error Handling`.

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

Find the last bullet in `## Error Handling` (likely "Missing workflow status...") and append the canonical content from spec section **"Canonical content for plan tasks → C5: Self-Learning loop failures sub-section"** after it.

The Edit shape:
- `old_string`: that last existing bullet of `## Error Handling`.
- `new_string`: same bullet + a blank line + the full C5 spec block (the `### Self-Learning loop failures` heading and table).

If the last bullet in your file is different, adapt `old_string` to match exactly — the *insertion landmark* is "after the last existing bullet of `## Error Handling`, still inside that section".

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

- [ ] **D11: Toggle OFF — orchestrator silence.** Run `/sdlc lessons off`. Send a clear user correction ("always use git -C, never cd && git"). Pass: no extractor spawn (no `Agent()` call to lesson-extractor), no journal write, no surfaced proposal. Phase routing unaffected. The auto-resume file shows `enabled: false`.

- [ ] **D12: Toggle OFF — agent silence.** Run `/sdlc lessons off`. Run a story with deliberately-failing setup that would normally cause the agent to retry and emit `## Lessons`. Pass: the agent's return text contains no `## Lessons` section. Verify by reading the agent's return verbatim.

- [ ] **D13: Toggle OFF — extractor safety net.** With toggle OFF, manually craft an extractor spawn (simulating a misbuilt orchestrator that ignored its own gate). Pass: extractor returns the exact verdict body `## Verdict: nothing-learnable\nReason: self-learning disabled in caller`, reads no candidate file (verify by absence of any Read tool call), writes no journal line.

- [ ] **D14: Toggle persistence across resume.** With an active epic, run `/sdlc lessons off`. Verify the resume file shows `enabled: false`. Open a fresh Claude Code session and run `/sdlc continue {EPIC-KEY}`. Pass: resume reads `enabled: false`, the loop stays off without re-prompting; first agent spawn's context line is `Self-Learning: OFF`.

- [ ] **D15: Toggle via LLM intent.** With toggle ON, send "this lesson stuff is too noisy, kill it for now". Pass: orchestrator confirms in one line and flips state to OFF (auto-resume file updated on next save). Then send "turn lessons back on". Pass: orchestrator flips state to ON. Verify by spot-checking the SDLC Context line value in the next agent spawn.

After D15: all smoke tests pass → v1 is shippable. Any failures: triage and patch the relevant Phase C task; do not move to v2.

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
| Source 1: user-correction (intent classification, maybe-confirm gate) | UserPromptSubmit hook (CSI-639) for capture + orchestrator drain (CSI-640); C2 documents the downstream lifecycle |
| Source 2: agent self-report (`## Lessons` block, parse rules) | B1-B13 (block in agents) + SubagentStop hook (CSI-638) for capture + orchestrator drain (CSI-640); C3 documents the downstream lifecycle |
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
| Hook-based capture (SubagentStop CSI-638, UserPromptSubmit CSI-639) + drain (CSI-640) | v1; landed/tracked separately — design spec Architecture + Hook-contracts sections |
| v2 future work (tool-call instrumentation, transcript scan for un-self-reported friction, /sdlc lessons commands) | Out of scope; design spec retains the outline |

**Gaps found and addressed inline:**
- The spec mentions persisting mode state in the auto-resume file but doesn't specify the format. Plan task C4 specifies the `## Mode` block format explicitly.
- The spec doesn't specify the journal bootstrap (creation on first event). Plan task C1 covers it.
- The spec doesn't specify how multi-block `## Lessons` returns are handled. Plan task C3 specifies "process each as a separate event."

**Placeholder scan:** No "TBD", "TODO", or "implement later" anywhere. Code blocks present where needed (the agent role file body, journal schema, surface formats, exact diffs for the orchestrator inserts).

**Type/name consistency:** Verdict names match across A1 and C2/C3 (`Proposal`, `Proposal (replace)`, `Recommendation`, `nothing learnable`). Status enum matches across C1, C2, C3, C5. Field names (`extractor_run`, `existing_rule`, `applied_commit`, `suggested_artifact`) match the spec's schema.

