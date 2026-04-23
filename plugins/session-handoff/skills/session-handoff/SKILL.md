---
name: session-handoff
description: >
  Capture session progress so the next session resumes without rediscovery.
  Use when the user says "save progress", "wrap up", "hand off", "pick up later",
  "save state", "checkpoint", "end of session", "park this", or before ending a long
  work session. Also trigger when the user mentions "resume", "continue later",
  "where was I", or wants to ensure continuity across sessions. Even if the user
  just says "done for now" or "stopping", use this to preserve context.
---

# Session Handoff

Capture everything the next session needs to resume immediately, without spending time on rediscovery.

## Why This Matters

A new session starts with zero memory of what happened. It has to read files, git history, Jira, and memory — which can take 10+ minutes and still miss context like decisions made verbally, dead ends explored, or blockers hit. This skill captures that perishable context before it's lost.

## Process

Work through these steps in order. Skip any that don't apply to the current session.

### 1. Scan Active State

Gather the current state without asking the user (they already know it — this is for the next session):

```
- git status: branch, uncommitted changes, ahead/behind remote
- git log -3: recent commits (what just happened)
- Task list: any pending/in-progress tasks
- Working directory: what project/repo are we in
- Active pipeline: if running /sdlc, which phase and story
```

### 2. Identify What Changed This Session

Summarize the session's work:
- What was the user's original goal?
- What decisions were made (and why)?
- What was completed?
- What was attempted but didn't work (dead ends)?
- What blockers were hit?
- What's the immediate next step?

Ask the user to confirm or add anything: "Here's what I'm capturing — anything to add or correct?"

### 3. Update Memory

Update or create the relevant project memory file in the memory directory.

Focus on:
- **Status** — update with today's date and what's done/in-progress
- **Decisions** — any choices made this session (tech, scope, approach) with reasoning
- **Blockers** — unresolved issues that the next session needs to know about
- **Next step** — the exact action to take when resuming

Use absolute dates (not "today" or "yesterday"). Remove stale information that's no longer true.

### 4. Update CLAUDE.md

If the project has a CLAUDE.md, update it:
- **Pipeline State** section — current phase, ticket statuses
- **Known Issues** section — new issues discovered
- **Ticket Map** — if new tickets were created, add them

Only update sections relevant to what changed. Don't rewrite the whole file.

### 5. Commit Checkpoint

If there are uncommitted changes:
- Show the user what would be committed
- Ask: "Commit and push these changes?"
- If yes, commit with message: `checkpoint: {brief summary of session work}`
- Push to the current branch

If no uncommitted changes, skip this step.

### 6. Write Handoff Summary

Output a clear, structured summary the user can glance at when starting the next session:

```markdown
## Session Handoff — {date}

### Project: {name}
### Branch: {branch}
### Repo: {path}

### Completed
- {what got done}

### Decisions Made
- {decision}: {why}

### In Progress
- {what's partially done}

### Next Steps
1. {exact first action for next session}
2. {second action}

### Blockers / Watch Out
- {anything the next session should know}

### Resume Command
{the exact command or /sdlc invocation to continue}
```

This summary goes to the user as output (not saved to a file — the memory and CLAUDE.md updates are the persistent record).

## Rules

- Scan state automatically — don't ask the user to list what happened
- Be specific — "CSI-45 is in Testing" not "some tickets are in progress"
- Use absolute dates — "2026-04-23" not "today"
- Don't duplicate — if something is already in CLAUDE.md or memory correctly, don't re-add it
- Keep it concise — the next session needs actionable context, not a narrative
- Always ask the user to confirm before committing
