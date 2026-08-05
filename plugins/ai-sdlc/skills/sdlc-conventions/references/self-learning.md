# AI-SDLC Self-Learning Loop (loaded on demand)

Loaded by the orchestrator at any "Drain check" marker when Self-Learning is ON (see the stub in `commands/sdlc.md` → "Self-Learning Loop"). This is the full contract: toggle/flag-file sync, curate flow, journal schema, drain procedure, extractor lifecycle + tiered routes, mode 1/2 surfacing, the `## Mode` and `## Docs` auto-resume blocks, and failure handling.

Lessons come from two sources (v1): user corrections and agent `## Lessons` self-reports. **Capture is done by the hooks, not the orchestrator.** The `UserPromptSubmit` hook (CSI-639) classifies user corrections at submit time. Agent self-reports are captured by **two** hooks so the source doesn't matter: the `PostToolUse`/`Agent` hook (CSI-644) reads each sub-agent's return text from the tool payload's `tool_response.content`, and the `SubagentStop` hook (CSI-638) reconstructs it from the transcript. **`/sdlc` spawns every sub-agent via the `Agent` tool (never `subagent_type`), so `SubagentStop` never fires for it — the `PostToolUse`/`Agent` hook is the one that actually captures `## Lessons` in this pipeline.** `SubagentStop` remains only for `Task`-tool typed subagents. All three deterministically append `status: "raw"` events to the journal regardless of whether the orchestrator was paying attention. The orchestrator's only job is to **drain the raw queue**: read those `raw` events, spawn the `sdlc-lesson-extractor` sub-agent per event (it classifies fix type and returns a structured verdict), and drive each through the proposed→approved/rejected lifecycle. Approved text-edit verdicts apply directly to canonical files; non-text verdicts (hook / script / skill / slash-command) surface as recommendations the user implements manually.

See `docs/specs/2026-06-10-ai-sdlc-self-learning-design.md` for the full design.

### Toggle (on/off) — gate this entire section

**State:** held in orchestrator memory, persisted to the auto-resume file under `## Self-Learning` → `enabled: true|false`. Default `true` when missing. Restored on Phase 0 fast resume.

**Propagation:** every agent spawn's SDLC Context block includes the line `Self-Learning: ON` (or `OFF`). Built deterministically from the in-memory state.

**Hard gate:** if the toggle is OFF for the current session, the orchestrator MUST:
- skip the raw-queue drain entirely (do not read or process `raw` events),
- NOT spawn `sdlc-lesson-extractor`,
- NOT write to `sdlc-events.jsonl`,
- ensure the hook-readable disable flag file `~/.claude/projects/-Users-maorb-git-dev/memory/.sdlc-lessons-disabled` **exists** (so the capture hooks are silent too — they gate on this same file),
- and continue normal phase routing as if this section did not exist.

**Flag-file ownership (the toggle bridge).** The resume-file `## Self-Learning` → `enabled:` line is the human-readable state; the `.sdlc-lessons-disabled` flag file is the hook-readable state (defined by CSI-638). The orchestrator owns keeping them in sync: on **OFF**, `touch` the flag file; on **ON**, remove it (`rm -f`). Do this on every `/sdlc lessons on|off` flip and on every LLM-intent enable/disable, before continuing.

**Toggling:**
- **Slash command:** `/sdlc lessons on|off` flips state, writes/removes the flag file, persists, confirms in one line. `/sdlc lessons` (no arg) reports current state.
- **LLM intent:** classify free-form user text as `disable` ("turn off self-learning", "too noisy, stop capturing"), `enable` ("turn lessons back on"), or `irrelevant`. On `disable`/`enable`: confirm in one line, write/remove the flag file, update state, persist on next auto-save.
- On every flip, the next agent spawn's context line reflects the new value.

### Curate (subtractive loop) — `/sdlc lessons curate`

> **STATUS: SCAFFOLD — not yet smoke-tested.** Wiring is present; the flow below is the contract, not a validated path. See `docs/specs/2026-07-08-ai-sdlc-memory-curator-design.md` for the full design.

The curator is the **subtractive inverse** of the extractor: where the extractor ADDS one rule under a cost gate, the curator finds duplicated / contradictory / superseded / stale content to REMOVE under a safety gate. It runs **on-demand only** (v1 — no auto-offer, no schedule). All corpus-reading happens inside the `sdlc-curator` sub-agent's throwaway context, so the main session never ingests the corpus — running it has zero standing context cost.

**Flow:**

1. **Toggle hard-gate.** If Self-Learning is OFF, refuse: *"Self-learning is off; curation is part of the same loop. Turn it on with `/sdlc lessons on` first."* Do not spawn.
2. **Resolve the corpus** (the command layer globs so the agent stays bounded), grouped by tier:
   - **always-loaded:** `plugins/ai-sdlc/agents/sdlc-*.md`, `plugins/ai-sdlc/commands/sdlc.md`, `~/.claude/projects/-Users-maorb-git-dev/memory/feedback_*.md` + `MEMORY.md`, repo-local `CLAUDE.md`, user global `CLAUDE.md`/`RTK.md`.
   - **on-demand:** `plugins/ai-sdlc/skills/*/SKILL.md`, `plugins/ai-sdlc/skills/*/references/*.md` (incl. `recipes-*.md`), other `~/.claude/projects/.../memory/*.md`.
   - **never-loaded:** the journal `sdlc-events.jsonl`.
   Resolve repo root, plugin root, journal path.
3. **Spawn `sdlc-curator`** via the standard general-purpose `Agent()` pattern (per "How to Spawn Agents"). Pointer to `Agent Paths.curator`. Prompt body:
   ```
   Corpus:
     always-loaded: <file list>
     on-demand: <file list>
     never-loaded: <journal path>
   Journal Path: ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
   Repo Root: <repo root>
   Plugin Root: <plugin root>
   Top-N: 15
   Self-Learning: ON
   ```
4. **Surface the ranked proposal** as a batch (reuse the mode-2 batch surface shape): the `Total potential savings` line, then each candidate block, then: `Approve all / Reject all / Per-item (1: a/r, 2: a/r, ...)`.
5. **Per-item apply on approval** (the curator NEVER edits — the orchestrator does, exactly as with lesson proposals):
   - `delete` / `archive` (Tier A) → Edit removes the recipe block; journal archival moves resolved lines to `sdlc-events.archive-YYYY-MM.jsonl` (reuse the manual-rotation convention).
   - `consolidate` (Tier B) → Edit removes the duplicate copy from the **non-canonical** file only; the canonical file is untouched (add a one-line pointer only if the resolution says so).
   - `resolve-contradiction` (Tier B) → Edit the losing side to defer to the winner the user picked at the gate.
   Do NOT auto-commit (v1 — the user commits when ready). Rejected candidates apply no edit.
6. **Journal each action** with the curator schema variant: `source: "curator"`, `agent: "sdlc-curator"`, `curator_run: { category, tier, action, targets, leverage, resolution }`, `status: proposed → approved | rejected` (or `archived`). Same append-only, latest-line-per-`id` mechanics as the additive loop.
7. **Anti-thrash guard.** If the curator flagged a candidate `recently-added — confirm intent` (the same content was added by an approved lesson within the last 50 events), surface that note prominently so the user doesn't undo a fresh lesson by reflex.

**Safety invariant (enforced by the curator, re-checked here):** a Tier-B (always-loaded) candidate is NEVER a silent `delete` — only `consolidate` (the rule survives in the canonical file) or `resolve-contradiction` (both sides shown, user picks). If a proposal ever shows `Tier: B` with `Action: delete`, reject it and note the contract violation.

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
          | "nothing-learnable" | "logged-recipe" | "extraction-failed" | "stale"
          | "suppressed-duplicate-rejection",
  "applied_commit": "<sha or null>"
}
```

`logged-recipe` is terminal — a one-off lesson recorded, not codified (no edit applied); a later recurrence is promoted to a real proposal via the existing repetition counter (see "Draining the raw queue" / the extractor's repetition detection).

Logical updates: append a new line with the same `id` and a new `status`. Readers always take the latest line per `id`. Reverting an update = delete the latest line for that id.

Bootstrap: the journal file is created on the first event (Bash: `mkdir -p $(dirname <journal>) && touch <journal>` if absent). Never fail the SDLC pipeline because the journal can't be written; if writes fail (disk/permission/IO), surface a hard error and halt the lesson loop for the session, but continue the SDLC pipeline.

### Draining the raw queue

The hooks (CSI-644 PostToolUse/Agent, CSI-638 SubagentStop, CSI-639 UserPromptSubmit) deposit `status: "raw"` events into the journal asynchronously. The orchestrator does **not** watch every turn for lessons — it *drains* these raw events at deterministic points and advances each through the lifecycle. This is the orchestrator's only capture-adjacent responsibility; detection itself lives entirely in the hooks.

**1. When to drain.** Run the drain as the FIRST action of this Self-Learning Loop whenever the orchestrator regains control — i.e. at the START of every orchestrator turn that follows agent work or a user message — AND at every phase boundary already enumerated for mode 2 (end of Phase 1, 1.5, 2, 3, 3.5, 3.6, per-batch in Phase 4, per-story in Phases 5/6/7, per-merge-run in 7.5, and Phase 8). This replaces the old "on every user message classify intent" and "after every agent return scan for `## Lessons`" behavior — those detections now happen in the hooks.

**2. Toggle hard-gate.** If Self-Learning is OFF (see the Toggle sub-section), **skip the drain entirely** — do not read or process the journal — and ensure the `.sdlc-lessons-disabled` flag file exists so the capture hooks are silent too. Only proceed with steps 3-7 when Self-Learning is ON.

**3. Read the queue.** Read the journal, build latest-line-per-`id`, and select the `id`s whose latest line has `status == "raw"`. Bash recipe:
```bash
J=~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
[ -f "$J" ] || exit 0
# latest line per id, then keep only those whose latest status is "raw"
tac "$J" | jq -c -s '
  ([.[] | {id, line: .}] | group_by(.id) | map(.[0].line))
  | map(select(.status == "raw"))' 2>/dev/null
# (macOS lacks tac: use `tail -r` instead of `tac`.)
```
Each raw event already carries `source`, `evidence`, `agent`, `trigger_summary` (written by the hooks per the CSI-638 schema). Backfill `epic`/`phase`/`story` from current orchestrator state when the event has them `null`.

**4. Per raw event — near-duplicate suppression (BEFORE spawn).** Scan the journal for a prior event with the SAME `source`, evidence-similar (single short comparison call), `status: rejected`, within the last 50 events. If found:
1. Append a new event (same `id` as the raw one) with `status: suppressed-duplicate-rejection` (no `extractor_run`).
2. Surface one line: *"Similar correction was rejected on <date> — not re-proposing. Override with: 'extract anyway'."*
3. Do NOT spawn the extractor; move to the next raw event.

**5. Spawn the extractor.** Use the standard general-purpose `Agent()` spawn pattern (per "How to Spawn Agents"). Pointer to `Agent Paths.lesson-extractor`. The hook already wrote the `status: raw` line, so do NOT append another `raw` line — proceed straight to the spawn. Build the prompt body from the raw event:
```
Source: <event.source>            # user-correction | agent-self-report
Evidence: <event.evidence>         # verbatim — the ### Lesson block (self-report) or prompt + recent actions (correction)
Context: agent=<event.agent>, story=<event.story or null>, epic=<event.epic or orchestrator state>, phase=<event.phase or orchestrator state>
Target candidate: <see below>
Journal Path: ~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl
Self-Learning: ON
```
- For `agent-self-report`: parse the `Suggested target:` field out of the `### Lesson` evidence block and use it as `Target candidate` (extractor may override).
- For `user-correction`: apply the "Target candidate selection" priority list (in the Source 1 sub-section below).

**6. Lifecycle.** After the extractor returns:
- On `nothing-learnable` → append `status: nothing-learnable` (terminal). No surface.
- On `Proposal` / `Proposal (tiered)` / `Proposal (replace)` / `Recommendation` → append `status: proposed` with the full `extractor_run` object.
- In mode 1, surface the proposal immediately (see "Surface format"). In mode 2, queue and continue.
- On user approval (`Proposal`/`Proposal (replace)`): apply the Edit, append `status: approved` with `applied_commit: <sha or null>` (orchestrator does NOT auto-commit lesson edits in v1).
- On user approval (`Proposal (tiered)`): the user picks route `a` / `b` / `c` — apply it per "Applying a tiered route" below, then append the resulting `status`.
- On Recommendation approval: nothing to apply automatically — append `status: approved` with `applied_commit: null`; the user implements it manually.
- On user rejection: append `status: rejected`.

**6a. Applying a tiered route.** The `## Proposal (tiered)` verdict carries the three signals and the three route targets but **no `## Diff` block** — the extractor deliberately does not author the edit for a tiered lesson. When the user picks a route, the orchestrator composes the minimal edit itself from the verdict's `Trigger` (and the evidence), phrased imperatively ("Always … / Never …"):
- **`a` (Principle)** → apply an Edit to the always-loaded canonical file named in route `[a]` (a role file / `feedback_*.md` / `CLAUDE.md`), adding one concise imperative line located near related existing rules. Append `status: approved` with `applied_commit: <sha or null>` (do NOT auto-commit). This is the existing text-edit behavior; the orchestrator supplies the line because the tiered verdict omitted the diff.
- **`b` (Recipe)** → append the lesson as a recipe to `plugins/ai-sdlc/skills/sdlc-conventions/references/recipes-{domain}.md` (the `{domain}` from route `[b]`; create the file with its format header — see an existing `recipes-*.md` — if absent). Use the per-recipe three-field shape: `### <short title>` then **Trigger** / **Recipe** / **When-it-rots**. THEN ensure the relevant agent role file(s) carry the one-line on-demand pointer to that recipe file (`See \`../skills/sdlc-conventions/references/recipes-{domain}.md\` for {domain} tooling gotchas — load on demand.`); add it if missing (convention in `sdlc-conventions/SKILL.md` → "On-Demand Recipes"). Append `status: approved` with `applied_commit: <sha or null>`.
- **`c` (One-off)** → append `status: logged-recipe` (terminal, no file edit). Reuse this existing status; do not redefine it. A later recurrence is promoted to a real proposal by the extractor's repetition counter.

**Multiple raw events.** Process each as a separate event (they may target different files). Self-learning runs alongside phase routing and never blocks it: in mode 1 an inline approval pauses the current turn until the user responds; in mode 2 routing continues and proposals flush at the next boundary.

### Source 1: user-correction

**Capture is done by the hook, not the orchestrator.** The `UserPromptSubmit` hook (CSI-639) classifies every user prompt out-of-band (keyword pre-filter → Haiku classifier) and, on a high-confidence correction, appends a `source: "user-correction"`, `status: "raw"` event to the journal. The orchestrator does **not** classify user messages for capture — it picks these events up in the drain step (see "Draining the raw queue" above). Do NOT re-implement intent classification here.

**Target candidate selection.** The drain step needs a `Target candidate` for the extractor prompt on a user-correction event. Use this priority:
1. If the correction is about a specific named agent's behavior → that agent's role file.
2. If about an orchestrator phase or flow → `plugins/ai-sdlc/commands/sdlc.md`.
3. If a cross-cutting principle (applies to all of Maor's work) → most relevant `~/.claude/projects/.../memory/feedback_*.md` (or "create new feedback file" if none fits).
4. If project-specific (only this repo) → that repo's `CLAUDE.md`.
5. If unsure → pass the orchestrator file as candidate; the extractor will override if needed.

### Source 2: agent-self-report

**Capture is done by the hooks, not the orchestrator.** Two hooks share one parser (`emit_lessons_from_text` in `hooks/lib/journal-append.sh`) that scans for the literal `## Lessons` header and parses every well-formed `### Lesson` block (Trigger / Generalizable rule / Suggested fix type / Suggested target — an optional `- `/`* ` bullet marker is tolerated; malformed blocks are skipped with a sidecar warning), appending one `status: "raw"` event per block:
- **`PostToolUse`/`Agent` (CSI-644, source `agent-tool-return`)** — reads the sub-agent's return text from the payload's `tool_response.content` content-block array. **This is the hook that fires for `/sdlc`**, because `/sdlc` spawns agents via the `Agent` tool.
- **`SubagentStop` (CSI-638, source `agent-self-report`)** — reconstructs the return text from the transcript. Fires only for `Task`-tool typed subagents (kept for compatibility; does NOT fire for `/sdlc`).

The orchestrator does **not** scan agent returns for `## Lessons` — it picks these events up in the drain step (see "Draining the raw queue" above). The `Suggested target:` field is preserved verbatim in the event's `evidence`, so the drain step can parse it for the extractor's `Target candidate`. Do NOT re-implement the return-scan or `### Lesson` parsing here.

### Surface format (mode 1, immediate)

When a proposal becomes ready, surface this to the user as a single message block:

```
📚 Lesson proposal — <Source> on <agent>/<story or epic>
Trigger: <trigger_summary>

<Verdict block as returned by the extractor — Proposal | Proposal (replace) | Recommendation>

Approve / Reject?
```

On user response:
- "approve" / "yes" / "apply" → Edit (for text-edit verdicts) or log-only (for Recommendation), append `status: approved`, brief one-line confirmation.
- "reject" / "no" / "skip" → append `status: rejected`, one-line confirmation.
- For mode-1, "defer" is not offered (it's a mode-2 concept).

Then continue with whatever phase work was in progress.

**Tiered proposals (`## Proposal (tiered)`).** When the extractor's verdict is `## Proposal (tiered)`, surface the cost-at-decision-time signals and the three routes verbatim so the human weighs the always-loaded cost before choosing — this visible cost is the core of the fix. The verdict has no diff; do NOT ask a bare Approve/Reject. Surface:

```
📚 Lesson proposal (tiered) — <Source> on <agent>/<story or epic>
Trigger: <trigger_summary>

Generality: <RECIPE | PRINCIPLE | MIXED> (names: <detected tokens>) · <scope note>
Recurrence: <N> prior events (<one-off | earned>)
Cost if always-loaded: <what a permanent slot costs>

Route options:
  [a] Principle → <always-loaded target: role file / feedback_*.md / CLAUDE.md>
  [b] Recipe   → references/recipes-<domain>.md   (on-demand)
  [c] One-off  → log only (status: logged-recipe)
Recommended: <a | b | c>

Pick a route (a / b / c) or Reject?
```

On user response:
- `a` / `b` / `c` → apply that route per "Applying a tiered route" (step 6a above), then append the resulting `status` (`approved` for a/b, `logged-recipe` for c), with a one-line confirmation naming the file(s) touched.
- "reject" / "no" / "skip" → append `status: rejected`, one-line confirmation.

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
   [2] (tiered) <Source> • <trigger_summary>
       Generality: <RECIPE|PRINCIPLE|MIXED> · Recurrence: <N> (<one-off|earned>) · Cost: <always-loaded cost>
       Routes: [a] <always-loaded target>  [b] recipes-<domain>.md  [c] log-only · Recommended: <a|b|c>
   ...

   Approve all / Reject all / Defer all to next phase / Per-item (1: a/r/d, 2: a/r/d, ...)
   ```
   For a `## Proposal (tiered)` item, render the Generality / Recurrence / Cost signals and the three [a]/[b]/[c] routes with the Recommended hint (as shown for item [2]) so the always-loaded cost is visible before the human decides — a bare one-line summary is not enough for a tiered item. Plain (non-tiered) items keep the single abbreviated-verdict line.
2. On user response:
   - "approve all" → for each: plain/replace verdicts apply their Edit; `Recommendation` is log-only; a **tiered** item applies its **Recommended** route (step 6a). Append the resulting `status` per item (`approved`, or `logged-recipe` when a tiered item's recommended/chosen route is `c`).
   - "reject all" → append `status: rejected` for each.
   - "defer all" → append `status: deferred` for each; re-queue at the start of the next phase.
   - Per-item like `1: a, 2: r, 3: d` → apply each verb to its event. For a tiered item, a per-item route letter (`a`/`b`/`c`) selects that route explicitly (overriding Recommended); `r` rejects, `d` defers.
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

### Docs state in the auto-resume file

Phase 7.7 (`--docs`) persists its state so it survives `/sdlc continue` and the Confluence target is asked only once per project. Add:

```
## Docs
enabled: true | false          # mirrors the --docs flag; default false if absent
confluence_space: <key> | none | unset   # "unset" = not yet asked; "none" = user declined
confluence_parent: <id> | unset
```

On `Phase 0 → Fast Resume`, restore `enabled` into the in-memory `--docs` state (so a resumed run keeps documenting). If the block is absent, default to `enabled: false, confluence_space: unset, confluence_parent: unset`. On the first auto-save after `--docs` is seen on the command line, write `enabled: true` explicitly.

## Failure modes

| Failure | Response |
|---|---|
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
| Correction-intent classified `yes→maybe` | Hook emits no event (CSI-639: `maybe` is a no-op for schema parity). Lesson not captured. Acceptable: user can repeat more emphatically. |
| Agent omits `## Lessons` despite friction | Not caught in v1. v2's transcript scan + hooks closes this gap. Acceptable known gap. |
| Agent over-reports (lesson for already-covered rule) | Extractor's existing-rule detection handles it (rewrite / recommend / move / nothing-learnable). Never silently discarded. |
| Agent suggests wrong target | Extractor's classification overrides. Suggestion is a hint, not authoritative. |
