---
name: sdlc-handoff
description: >
  Save AI-SDLC pipeline state for fast resume in the next session. Invoke when pausing
  SDLC work, at the end of a batch, or when context is getting large. Writes a resume
  file that lets Phase 0 skip full discovery (~15-20k token savings on resume).
  Trigger when: user says "pause", "save sdlc state", "handoff", or the orchestrator
  finishes a batch and context is above 60%.
---

# SDLC Handoff

Save the current AI-SDLC pipeline state so the next session can resume in seconds instead of re-discovering everything from Jira — both the technical context (transition maps, routing) and the human context (decisions, dead ends, blockers).

## When to Trigger

- User says "pause", "stop", "save progress", "handoff"
- Orchestrator finishes a batch (all stories in a wave reached their next phase gate)
- Context window exceeds 60% used
- End of session (before `/compact` or context exhaustion)

## Process

### 1. Scan Active State

Gather the current state automatically — don't ask the user to list what happened:

**Git state (per active worktree):**
```bash
# For each worktree in {repo_path}.worktrees/
git -C {worktree} status --short
git -C {worktree} log --oneline -3
git -C {worktree} rev-parse --abbrev-ref HEAD
# Check if ahead of remote
git -C {worktree} rev-list --count @{u}..HEAD 2>/dev/null
```

**Pipeline state:**
- Epic key being worked on
- All story keys with their current Jira status
- Which phase each story should enter next (routing table)
- Active worktrees and their branches
- The full SDLC context block (project key, cloudId, transition map, agent paths, base branch, PR target)

**Session context:**
- What was the user's original goal this session?
- What decisions were made (and why)?
- What was completed?
- What was attempted but didn't work (dead ends)?
- What blockers were hit?
- What's the immediate next step?

### 2. Identify Uncommitted Work

For each active worktree, check if there are uncommitted changes:

```bash
git -C {worktree} status --short
```

If there are uncommitted changes:
- List the changed files
- Show to the user
- Ask: "Commit and push these changes before saving state? (y/n)"
- If yes: commit with message `checkpoint: {STORY-KEY} — {brief summary}` and push
- If no: note in the resume file that uncommitted work exists

### 3. Confirm with User

Present a draft summary to the user before writing:

```
Here's what I'm capturing for {EPIC-KEY} — anything to add or correct?

Completed: {list}
Decisions: {list}
Dead ends: {list}
Blockers: {list}
Next step: {action}
```

Wait for user confirmation or additions. Incorporate their feedback.

### 4. Write the Resume File

Write to `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-resume-{EPIC-KEY}.md`:

```markdown
---
name: sdlc-resume-{EPIC-KEY}
description: Cached SDLC state for fast resume of {EPIC-KEY} — skip Phase 0 discovery
metadata:
  type: project
---

## Context Block

Project Name: {product_name}
Project Key: {projectKey}
Cloud ID: {cloudId}
Repo Path: {repo_path}
Base Branch: {base_branch}
PR Target: {pr_target_branch}
QBV Key: {qbv_key}
Epic Key: {EPIC-KEY}
Transition Map: {full map as JSON — e.g., {"To Do": "11", "In Progress": "21", ...}}
Agent Paths: {full map as JSON — e.g., {"planner": "/path/...", "developer": "/path/...", ...}}

## Mode
{current operating mode: `normal`, `feedback-loop`, `hotfix`, or `fast`}

## Self-Learning
enabled: {true|false}

## Codex
enabled: {true|false}   # omit the block only if Codex was never toggled this session

## Docs
{--docs settings if set: confluence_space, confluence_parent — omit the block if --docs was not used}

## Story Routing Table

| Key | Title (short) | Status | Next Phase | Branch | Notes |
|-----|---------------|--------|------------|--------|-------|
| {key} | {title} | {status} | {phase} | {branch} | {worktree exists / blocked / done} |

## Session Notes

### Completed This Session
- {what got done — be specific with ticket keys and phases}

### Decisions Made
- {decision}: {why} (alternative considered: {what was rejected})

### Dead Ends / What Didn't Work
- {approach that failed}: {why it failed, so next session doesn't retry}

### Blockers
- {blocker}: {what's needed to unblock, who can help}

### Approach / Architecture Notes
- {any non-obvious technical decisions that affect future stories}

## Last Action

- Date: {YYYY-MM-DD}
- Next: {exact first action for resume — e.g., "spawn tester for CSI-443"}

## Active Worktrees

- {repo_path}.worktrees/{STORY-KEY} (branch: {branch-name}, uncommitted: {yes/no})

## Git State

| Worktree | Branch | Ahead | Uncommitted | Last Commit |
|----------|--------|-------|-------------|-------------|
| {STORY-KEY} | {branch} | {N commits} | {yes/no} | {short sha + message} |
```

**Fast-wave variant (`Jira: off`).** A fast wave has **no Jira epic key**, so it must not be saved as an epic-keyed file. Instead:
- Name the file `sdlc-resume-{WAVE-ID}.md` (`{WAVE-ID}` = `{PROJECT}-W{YYYYMMDD-HHMMSS}`, same memory dir).
- Replace the `## Story Routing Table` (there are no Jira statuses to route on) with the two fast-mode blocks the orchestrator's auto-save uses (see `commands/sdlc.md` → "Fast-mode resume file"):
  ```
  ## Wave
    id: {WAVE-ID}
    project: {PROJECT}
    mode: fast
    plan_file: docs/sdlc/_wave-{WAVE-ID}/plan.md
    reconciled: false            # or the {QBV-KEY} once Phase 8.5 back-fills Jira

  ## Fast Work Ledger
    {one YAML entry per work unit — full schema in `sdlc-conventions` §2.6:
     key, title, epic, ac[], complexity, deps[], phase, branch, pr, spec_files[], bugs[], verdicts, jira}
  ```
- Keep `## Context Block`, `## Mode` (`fast`), `## Self-Learning`, `## Codex`, `## Session Notes`, `## Last Action`, `## Active Worktrees`, `## Git State` exactly as above.
- The canonical ledger copy also lives at `docs/sdlc/_wave-{WAVE-ID}/ledger.md` (committed each phase), so a resume can rebuild state even if this memory file is lost.

### 5. Update MEMORY.md

Ensure a pointer exists in the memory index:

```
- [SDLC Resume: {EPIC-KEY}](sdlc-resume-{EPIC-KEY}.md) — cached state for fast /sdlc resume
```

If a pointer already exists, leave it (no duplicate).

### 6. Update Project CLAUDE.md (if applicable)

If the project has a CLAUDE.md with a pipeline state or known issues section, update it:
- **Pipeline State** — current phase, which stories are in which status
- **Known Issues** — any new issues discovered this session
- **Ticket Map** — if new tickets were created, add them

Only update sections relevant to what changed. Don't rewrite the whole file.

### 7. Report to User

Output a structured handoff summary:

```markdown
## SDLC Handoff — {YYYY-MM-DD}

### Epic: {EPIC-KEY} ({product name})
### Repo: {repo_path}
### Branch: {base_branch}

### Completed
- {what got done}

### Decisions Made
- {decision}: {why}

### In Progress
- {what's partially done, with story keys}

### Next Steps
1. {exact first action for next session}
2. {second action}
3. {third action if applicable}

### Blockers / Watch Out
- {anything the next session should know}

### Resume Command
`/sdlc continue {EPIC-KEY}`   (fast wave: `/sdlc continue {WAVE-ID}`)
```

## Routing Rules Reference

Use these to fill the "Next Phase" column:

| Status | Next Phase |
|--------|-----------|
| Backlog / To Do | Phase 3 (Architecture) |
| Selected for Development / Ready for Dev | Phase 4 (Develop) |
| In Progress + open child Bugs | Phase 7 (Bug Fix) |
| In Progress + no bugs | Phase 4 resume |
| In Review | Phase 5 (Test) |
| Testing | Phase 6 (QA) |
| Done | skip |

**Fast wave (`Jira: off`):** there are no Jira statuses — do not build a status routing table. Route from the ledger `phase` field instead (`architected` / `ready` / `in-progress` / `in-review` / `testing` / `done` / `blocked`); see `sdlc-conventions` `references/workflow-states.md` → "Fast Mode — Ledger Phase ↔ Jira Status".

## Rules

- **Scan state automatically** — don't ask the user to list what happened
- **Be specific** — "CSI-443 is In Review, tester next" not "some tickets are in progress"
- **Use absolute dates** — "2026-05-26" not "today" or "yesterday"
- **Don't duplicate** — if something is already in CLAUDE.md or memory correctly, don't re-add
- **Ask for confirmation** — always show the draft to the user before writing
- **Commit checkpoint if uncommitted work exists** — ask first, never force-commit
- **Capture dead ends** — these are the most valuable thing for the next session; without them, it'll retry the same failed approaches
- **Keep it concise** — the next session needs actionable context, not a narrative
- **Overwrite, don't append** — the resume file replaces any previous version for the same epic
- **Mark unknowns** — if you can't determine a value, write `{UNKNOWN — will rediscover}` rather than guessing
- **Delete on completion** — when a **normal** epic reaches Phase 8 (all stories Done), delete the resume file. **Fast-wave exception:** keep `sdlc-resume-{WAVE-ID}.md` until the wave is **reconciled** (Phase 8.5 sets `## Wave.reconciled` to a QBV key) or the user **explicitly abandons** it — a plain reconciliation *decline* does NOT delete it (see `commands/sdlc.md` → "Cleanup"). Otherwise a later `/sdlc continue {WAVE-ID}` cannot find the wave to back-fill Jira.
