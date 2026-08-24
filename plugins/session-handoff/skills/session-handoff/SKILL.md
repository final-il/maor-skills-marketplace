---
name: session-handoff
description: >
  Capture session progress so the next session resumes without rediscovery.
  Writes a dated handoff file under docs/handoffs/ (committed alongside the work) and,
  on resume, reads the most recent one to restore context.
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

**Memory vs. the handoff file — keep them separate.** Memory holds *durable* facts (who the user is, standing preferences, project constraints). The handoff file holds *perishable* "resume here" state (what's half-done, the exact next step, today's blockers) — true for one resume, then superseded. Don't put transient resume-state in memory (it rots and the curator has to prune it); don't put durable facts only in a handoff file (it scrolls out of the trail). Write each to its own place.

## Two directions: save and resume

Run in whichever direction the trigger implies:

- **Save** (default) — "save progress", "hand off", "done for now", "checkpoint": run the Process below to capture state and write the handoff file.
- **Resume** — "where was I", "continue", "pick up where we left off": **first read the most recent file in `docs/handoffs/`** (fall back to `.claude/handoffs/` if that's where this repo keeps them). Treat its **Next Steps** as the starting point and confirm them with the user before acting; skim the file just before it only if you need *how* a decision was reached. The newest dated file is always the resume point.

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
- **Handoff pointer** — ensure a one-line instruction exists so a *fresh* session that never invokes this skill still knows where to resume. Add once (don't duplicate) under a short *Resuming* note, e.g.: `Session handoffs live in docs/handoffs/ — read the most recent before resuming.`

Only update sections relevant to what changed. Don't rewrite the whole file.

### 5. Write the Handoff File

Write the structured summary to a **dated, in-repo file** so it survives the session and teammates can see it — this is the artifact the next session reads to resume:

- **Path:** `docs/handoffs/{YYYY-MM-DD}-{short-slug}.md` (create `docs/handoffs/` if missing). If this repo has no `docs/` tree and you don't want to introduce one, use `.claude/handoffs/` — pick one location and stay consistent within a repo.
- **Keep history, never overwrite or delete.** One file per handoff, dated. Older handoffs are the trail of how the work evolved; "the latest file" is the resume point. If you write two on the same day, disambiguate with the slug (or a `-2` suffix).
- Write the file first, **then also print the same summary** to the user so they can glance at it now.

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

### 6. Commit Checkpoint

Stage the handoff file from Step 5 (plus any other session changes):
- Show the user what would be committed
- Ask: "Commit and push these changes?"
- If yes, commit with message: `checkpoint: {brief summary of session work}` and push to the current branch
- If the only change is the handoff file, still commit it — that's how the trail persists for teammates and the next session

## Rules

- Scan state automatically — don't ask the user to list what happened
- Be specific — "CSI-45 is in Testing" not "some tickets are in progress"
- Use absolute dates — "2026-04-23" not "today"
- **Handoff file is the resume artifact** — always write it (Step 5); the printed summary alone is ephemeral. On resume, read the newest one first.
- **Keep the handoff trail** — never overwrite or delete older handoff files; the newest is the resume point, the rest are history.
- **Durable → memory, perishable → handoff file** — long-lived facts go to memory; "resume here" state goes to the handoff file. Don't cross the streams.
- Don't duplicate — if something is already in CLAUDE.md or memory correctly, don't re-add it
- Keep it concise — the next session needs actionable context, not a narrative
- Always ask the user to confirm before committing
