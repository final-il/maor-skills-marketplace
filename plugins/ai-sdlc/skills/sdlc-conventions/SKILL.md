---
name: sdlc-conventions
description: >
  AI-SDLC Jira conventions and context protocol. This skill provides the standard templates,
  workflow states, and context-passing protocol used by all AI-SDLC agents. It is loaded
  as reference material by the /sdlc command and individual agents — not invoked directly.
  Use this skill when working with the AI-SDLC pipeline, when you need to understand
  how agents coordinate through Jira, or when creating/modifying SDLC agent definitions.
---

# AI-SDLC Conventions

## Overview

The AI-SDLC system uses Jira as the coordination layer between autonomous agents. Each agent reads its input from Jira tickets and writes its output back to Jira. This skill defines the shared conventions all agents follow.

## Jira Workflow

Stories flow through these statuses:

```
Backlog → Selected for Development → In Progress → In Review → Testing → Done
                                          ↑                           │
                                          └─── (defect: open child Bug) ─┘
```

On defect: Tester/QA creates a child **Bug issue** (issuetype=Bug) parented to the Story and transitions the Story to **In Progress**. The Bug Fixer transitions the Bug to Done and the Story to **In Review** for re-testing.

See `references/workflow-states.md` for full status definitions and the bug-fix detection JQL.

## Labels

All tickets created by the AI-SDLC system carry these labels:
- `ai-sdlc` — identifies tickets created/managed by the pipeline
- `phase-N` — the delivery phase (e.g., `phase-1a`, `phase-1b`)

## Ticket Structure

The system creates tickets in a 3-tier hierarchy:
- **QBV** (level 2) — One per product/project (e.g., "2c — Agent Conversation Visualizer")
- **Epic** (level 1) — Major functional area, parented to the QBV
- **Story** (level 0) — Implementable unit (1-3 days of work), parented to an Epic
- **Sub-task** — Optional fine-grained steps under a Story
- **Bug** — A child *issue* (issuetype=Bug, parented to the Story) created when tests/QA find a defect. Has its own status independent of the parent Story.

See `references/ticket-templates.md` for description templates.

## Context Protocol

Agents run in isolation. They share context through three channels:

1. **Agent prompt** — Structural metadata (cloudId, projectKey, repo path, issue keys, transition map)
2. **Jira tickets** — Primary channel. Requirements, tech specs, test results, bug reports (descriptions + comments)
3. **Project repo** — Code, CLAUDE.md, config files

See `references/context-protocol.md` for the full specification.

## Artifact Discipline

Every Jira read/write costs context tokens. Agents that pull the entire ticket "to be safe" balloon the context window and slow the pipeline. The rules below keep agents honest about what they read and write.

### 1. Per-phase artifact contract

Every agent has **exactly one output artifact** — the comment it posts at the end of its phase. The orchestrator's prompt to the agent tells it which prior artifacts (comments) to read. Agents do NOT scan the entire comment thread "for context."

The orchestrator's context block must include:

```
Read Artifacts:
  - Tech Spec (architect comment on {STORY-KEY})
  - Design Spec (designer comment on {STORY-KEY})  ← only if Phase 3.5 ran
Write Artifact:
  - Dev Result (post as comment on {STORY-KEY})
```

Agents read only the listed artifacts. If an agent finds it needs something else, it stops and asks the orchestrator rather than fetching the full ticket.

### 2. Summary header convention

Every artifact (every comment an agent posts) opens with a `## Summary` of 3-5 bullets, then detail below.

```markdown
## Summary
- Approach: streaming XML SAX parser (handles 100MB+ files)
- New module: `src/parsers/xml.py` exposing `parse_stream(io.IOBase)`
- Depends on stdlib `xml.sax` only — no new packages
- Test strategy: 5 fixture files covering malformed/valid/large
- Risk: SAX is callback-based; refactor needed if we want async later

## Detail
...
```

Downstream agents read the **summary first** and drill into detail only when their task requires it. Use the `Read` tool's `offset`/`limit` to window large artifacts. The writer of the artifact owns the summary; this is not lossy compression — the detail is always one read away.

### 3. What NOT to store in artifacts

- ❌ **Full test output** — Store `15/16 passed; failing: test_parse_malformed_xml (expected ValueError, got None at line 42)`. Re-run tests in the worktree if detail is needed.
- ❌ **Code snippets** — Reference commit SHA + file path. The worktree is the source of truth: `See src/parsers/xml.py:42-78 in commit abc1234`.
- ❌ **Restated requirements** — Don't quote the story description in the tech spec; don't quote the failing test source in the bug report. The reader has the same access you do.
- ❌ **Accumulating threads** — When an artifact is revised (e.g., bug-fixer updates dev-result), post a new comment that says "Supersedes prior dev-result; see commit XYZ" with a fresh summary. The Jira history preserves the prior version.
- ❌ **Full file contents** — Tech specs reference files by path; don't paste the file in.

### 4. Net effect

| Phase | Old default ("read the ticket") | With artifact discipline |
|---|---|---|
| Architect | full story desc + planner notes | story summary + acceptance criteria |
| Tester | story + tech spec + design + dev result | tech spec summary + dev-result summary + worktree |
| QA | everything above + test results | all summaries + test-result file |
| Bug-fixer | full thread | bug report + tech spec summary |

Roughly 40-60% reduction per agent run, no quality loss — detail is one targeted read away.

## Pipeline Phases

```
Phase 0: Init → Phase 1: Plan → Phase 2: Jira → Phase 3: Architect
  → Phase 3.5: Design (optional, user-facing stories only)
  → Phase 4: Develop → Phase 5: Test → Phase 6: QA → Phase 7: Bug Fix
  → Phase 8: Completion + Promotion
```

Phase 3.5 (Design) is skipped for purely backend stories. When it runs, the user approves the design before development begins.

## Branching Model

The pipeline supports two branching models, detected automatically in Phase 0:

**Dev/Prod model** (`dev` + `main` branches):
- Agents branch from `dev`, PRs target `dev`
- After all stories are Done, orchestrator offers to promote `dev` → `main`
- Context block sets: `Base Branch: dev`, `PR Target: dev`

**Single-branch model** (default):
- Agents branch from `main`, PRs target `main`
- Context block sets: `Base Branch: main`, `PR Target: main`

Agents never need to know which model is active — they use `{base_branch}` and `{pr_target_branch}` from the context block.

## Workspace Isolation — Git Worktrees

When the orchestrator runs multiple agents concurrently (e.g., developing two independent stories at once), they MUST NOT share a single working directory. A plain `cd {repo_path} && git checkout {branch}` from one agent yanks the working tree out from under the other.

The pipeline solves this with **git worktrees** — one worktree per story branch.

**Convention:**

- Worktrees are created as a sibling of the repo: `{repo_path}.worktrees/{STORY-KEY}`
  - Example: repo at `~/git/jiralyzer-dev` → worktree at `~/git/jiralyzer-dev.worktrees/CSI-105`
- The orchestrator (Phase 4 onward) creates the worktree before spawning the first agent for a story, and removes it in Phase 8 after the story reaches Done.
- Each agent prompt receives a `Worktree Path` field in the SDLC context block. Agents operate inside the worktree, NOT in the main `Repo Path`.
- The main `Repo Path` is for read-only operations only (reading `CLAUDE.md`, scanning project structure for context). All `git checkout`, edits, commits, and pushes happen in the `Worktree Path`.

**Lifecycle:**

```
Phase 4 (Developer):   orchestrator runs `git -C {repo_path} worktree add {worktree_path} -b {STORY-KEY}/{slug} {base_branch}`
                       → developer works in {worktree_path}
Phase 5 (Tester):      reuses the same {worktree_path} (story branch already checked out there)
Phase 6 (QA):          reads from {worktree_path} (read-only)
Phase 7 (Bug Fixer):   reuses the same {worktree_path}
Phase 8 (Completion):  after story is Done & PR merged, orchestrator runs `git -C {repo_path} worktree remove {worktree_path}`
```

**Same-story agents are serialized** — developer → tester → QA → bug-fixer all touch the same branch, so they run sequentially per story. Only **different stories run in parallel**, each in its own worktree.

**Why this matters:**

- Two developers branching from `dev` simultaneously no longer fight over `HEAD`
- A bug-fixer running on `STORY-A` cannot accidentally check out `STORY-A`'s branch in the main repo while the tester for `STORY-B` is mid-run
- `git status`, `git diff`, and `pytest` results are stable per agent
- If an agent crashes, the worktree is recoverable — `git worktree list` shows all live worktrees

**Cleanup rules:**

- The orchestrator owns the worktree lifecycle. Agents NEVER run `git worktree add` or `git worktree remove`.
- If a worktree path already exists when the orchestrator tries to create it (e.g., resuming a pipeline), reuse it — do not delete and recreate.
- If a story is abandoned/blocked, the orchestrator removes the worktree in Phase 8 along with the others.

## Required MCP Server: mcp-atlassian

The AI-SDLC pipeline requires the standalone `mcp-atlassian` MCP server (configured via `/mcp`). All Jira operations use `mcp__mcp-atlassian__jira_*` tools.

**IMPORTANT:** MCP tools are deferred — agents MUST use `ToolSearch` to load tool schemas before calling them.

**IMPORTANT:** Plugin subagents cannot access MCP tools (Claude Code limitation #25200, #38920). The orchestrator MUST spawn Jira-needing agents as general-purpose `Agent()` calls (no `subagent_type`) with the agent file body as the prompt. Only the planner (no Jira) can use typed subagent spawning.

| Operation | MCP Tool |
|-----------|----------|
| Search issues | `mcp__mcp-atlassian__jira_search` |
| Get issue details | `mcp__mcp-atlassian__jira_get_issue` |
| Create issue | `mcp__mcp-atlassian__jira_create_issue` |
| Update issue | `mcp__mcp-atlassian__jira_update_issue` |
| Add comment | `mcp__mcp-atlassian__jira_add_comment` |
| Transition status | `mcp__mcp-atlassian__jira_transition_issue` |
| Get transitions | `mcp__mcp-atlassian__jira_get_transitions` |
| Create link | `mcp__mcp-atlassian__jira_create_issue_link` |
| Link to epic | `mcp__mcp-atlassian__jira_link_to_epic` |
| List projects | `mcp__mcp-atlassian__jira_get_all_projects` |
| Look up user | `mcp__mcp-atlassian__jira_get_user_profile` |

## Agent Workflow Rules

1. **Load MCP tools first** — Use `ToolSearch` with `select:mcp__mcp-atlassian__jira_get_issue,...` before any Jira call
2. **Read only the artifacts your prompt names** — The orchestrator lists `Read Artifacts` in your context block. Read those, not the full comment thread. If you need something else, stop and ask the orchestrator.
3. **Write exactly one artifact** — Your phase produces one comment, and it opens with a `## Summary` of 3-5 bullets (see Artifact Discipline above).
4. **Never inline full output** — No full test logs, no pasted code, no restated requirements. Reference commits / file paths / failing test names instead.
5. **Use markdown in Jira** — The `mcp__mcp-atlassian__jira_add_comment` body parameter accepts Markdown directly
6. **Transition tickets** — Move tickets to the correct status when done
7. **On defect, create a child Bug and move the Story to In Progress** — Create a child issue with `issue_type: "Bug"` and `parent: {STORY-KEY}`, then transition the parent Story to **In Progress**. The Bug Fixer transitions the Story to **In Review** when the fix is pushed.
8. **Commit messages** — Always include the Jira ticket key: `{STORY-KEY}: {summary}`
9. **Branch naming** — Use `{story-key}/{short-slug}` (e.g., `PROJ-42/xml-parser`)
10. **PR target** — Always use `--base {pr_target_branch}` when creating PRs
11. **Operate in your worktree** — All git/edit/test commands run with `cd {worktree_path}` (or `git -C {worktree_path}`). Never `cd {repo_path}` for write operations. Never run `git worktree add/remove` from an agent — that is the orchestrator's job.

## Performance Rules — How Agents Use Jira

Every agent should treat Jira round-trips as the bottleneck of the pipeline. Follow these rules in every agent run:

### 1. Parallelize Jira reads and writes

When you need multiple independent Jira calls (e.g., reading a parent story + a child bug, or transitioning a ticket + adding a comment), issue them as **parallel tool calls in a single message**. Do NOT chain them sequentially.

**Examples:**
- Reading the bug + parent story → one message, two `jira_get_issue` calls
- Posting a result comment + transitioning status → one message, two calls
- Reading multiple stories in a batch → one message, N calls

The only time calls must be sequential is when the result of one is the input to the next (e.g., create issue → use returned key to create a link).

### 2. Use the transition map from the orchestrator's context block

The orchestrator discovers the project's transition IDs once in Phase 0 and passes them in every agent prompt as `Transition Map: {status_name: transition_id, ...}`.

**Always use the map first.** Do NOT call `mcp__mcp-atlassian__jira_get_transitions` on the happy path — the map already has what you need.

```
# Pseudo-code for transitioning to "Ready for Dev":
transition_id = transition_map["Ready for Dev"]
mcp__mcp-atlassian__jira_transition_issue(issue_key, transition_id)
```

**Fallback** — If the status you need is **not** in the map (rare; usually means the workflow has a status you haven't seen):
1. Load `jira_get_transitions` via ToolSearch
2. Call it once to find the missing transition ID
3. Proceed with `jira_transition_issue`
4. Note the missing status in your final Jira comment so the orchestrator can refresh the map

This means individual agents do NOT include `jira_get_transitions` in their startup ToolSearch — they only load it on miss.

### 3. Batch comment + transition where the API allows

A single status-change message often combines "post results" + "move to next status". Always issue them as **parallel calls**, not sequential — the order doesn't matter and the API handles both independently.
