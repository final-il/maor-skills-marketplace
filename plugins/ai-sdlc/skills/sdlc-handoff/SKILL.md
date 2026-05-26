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

Save the current AI-SDLC pipeline state so the next session can resume in seconds instead of re-discovering everything from Jira.

## When to Trigger

- User says "pause", "stop", "save progress", "handoff"
- Orchestrator finishes a batch (all stories in a wave reached their next phase gate)
- Context window exceeds 60% used
- End of session (before `/compact` or context exhaustion)

## Process

### 1. Gather Current State

Collect without asking the user (they already know it):

```
- Epic key being worked on
- All story keys with their current Jira status
- Which phase each story should enter next (routing table)
- Active worktrees (check: ls {repo_path}.worktrees/)
- Branch names per story
- The full SDLC context block (project key, cloudId, transition map, agent paths, base branch, PR target)
- What just completed and what's next
```

### 2. Write the Resume File

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

## Story Routing Table

| Key | Title (short) | Status | Next Phase | Branch | Notes |
|-----|---------------|--------|------------|--------|-------|
| {key} | {title} | {status} | {phase} | {branch} | {worktree exists / blocked / done} |

## Last Action

- Date: {YYYY-MM-DD}
- Completed: {what finished this session — be specific}
- Next: {exact first action for resume — e.g., "spawn tester for CSI-443"}

## Active Worktrees

- {repo_path}.worktrees/{STORY-KEY} (branch: {branch-name})
```

### 3. Update MEMORY.md

Ensure a pointer exists in the memory index:

```
- [SDLC Resume: {EPIC-KEY}](sdlc-resume-{EPIC-KEY}.md) — cached state for fast /sdlc resume
```

If a pointer already exists, leave it (no duplicate).

### 4. Report to User

Output a brief confirmation:

```
Saved SDLC state for {EPIC-KEY}.
Next session: `/sdlc continue {EPIC-KEY}` resumes in ~5s (skips full Phase 0).
Next action: {one-liner describing the exact next step}
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

## Rules

- Use absolute dates (YYYY-MM-DD), never "today" or "yesterday"
- Keep the routing table compact — omit Done stories unless they have notes
- The resume file replaces any previous version for the same epic (overwrite, don't append)
- If the orchestrator doesn't have the full context block in memory (e.g., fresh session), gather what you can from git state and conversation context; mark missing fields as `{UNKNOWN — will rediscover}`
- Delete the resume file when the epic reaches Phase 8 completion
