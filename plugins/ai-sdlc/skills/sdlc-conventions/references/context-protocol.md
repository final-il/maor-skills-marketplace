# AI-SDLC Context Protocol

## How Agents Share Context

Agents run in complete isolation — each agent starts with a fresh context window and no memory of previous agents. All context must be explicitly passed or stored in persistent systems.

## Three Context Channels

### Channel 1: Agent Prompt (Structural Metadata)

The orchestrator passes a standardized context block to every agent:

```
## SDLC Context
- Project Name: {product_name}
- Project Key: {projectKey}
- Cloud ID: {cloudId}
- Repo Path: {absolute_path_to_main_working_tree}
- Worktree Path: {absolute_path_to_per_story_worktree}   # Phase 4+ only
- Base Branch: {branch_agents_branch_from}
- PR Target: {branch_PRs_merge_into}
- QBV Key: {qbv_issue_key}
- Issue Keys: {comma-separated list of relevant Jira issue keys}
- Transition Map: Backlog={id}, Selected for Development={id}, In Progress={id}, In Review={id}, Testing={id}, Done={id}
  # Note: there is NO "Bug" key. `Bug` is an issue type, not a status. When a defect is found,
  # the parent Story is transitioned back to "In Progress"; child Bug issues have their own status.
- Read Artifacts: <list of prior comments/sections this agent should read; everything else is off-limits>
- Write Artifact: <the single comment this agent will post at the end of its phase>
```

**Base Branch** is the branch agents create feature branches from (e.g., `dev` or `main`).
**PR Target** is the branch PRs are opened against — usually the same as Base Branch.
In a dev/prod workflow (`dev` + `main` branches), both are `dev` during development. The orchestrator handles promotion to `main` separately.

**Repo Path** is the main checkout — used by the orchestrator and read-only by agents (e.g., to read `CLAUDE.md`).
**Worktree Path** is the per-story `git worktree` created by the orchestrator before Phase 4. Developer/tester/bug-fixer agents do ALL git operations and code edits in the worktree. This prevents concurrent agents from clobbering each other's checkouts. See `SKILL.md` ("Workspace Isolation — Git Worktrees") for details.

This block is injected into the agent's spawn prompt. It provides the structural information agents need to interact with Jira and the codebase.

### Channel 2: Jira Tickets (Primary Content Channel)

This is the **primary** channel for substantive context:

- **Story descriptions** contain requirements and acceptance criteria
- **Comments** are artifacts — exactly one per agent phase (tech spec, design, dev result, test result, QA review, bug report)
- **Status** indicates where in the pipeline a ticket is
- **Sub-tasks** (Bug type) contain bug reports

**Reading context from Jira (artifact discipline):**
```
1. Read only the artifacts listed in your prompt's "Read Artifacts" section.
2. Use ToolSearch to load: select:mcp__mcp-atlassian__jira_get_issue
3. Call mcp__mcp-atlassian__jira_get_issue once for the ticket.
4. Find the listed artifacts by their structured headers (## Tech Spec, ## Test Results, etc.)
   and read the ## Summary block first. Drill into detail only when your task requires it.
5. If you need an artifact that is not in the list, stop and tell the orchestrator —
   do not pull the whole comment thread.
```

**Writing context to Jira (one artifact per phase):**
```
1. Use ToolSearch to load: select:mcp__mcp-atlassian__jira_add_comment
2. Compose ONE comment that opens with `## Summary` (3-5 bullets), then `## Detail` below.
3. Reference commits / file paths / failing test names — never inline test logs,
   code, or restated requirements.
4. Follow the comment templates in ticket-templates.md.
```

### Channel 3: Project Repository

Agents read the codebase directly:

- `CLAUDE.md` — Project conventions, quick commands, architecture overview
- `pyproject.toml` / `package.json` — Dependencies, build config
- `src/` — Existing code patterns to follow
- `tests/` — Existing test patterns to follow

Agents also **write** to the repo (developer, tester, bug-fixer):
- Create branches, write code, commit, push, open PRs

## Context Flow Between Agents

```
Planner → (structured plan as text) → Orchestrator → (plan as prompt) → Jira Creator
Jira Creator → (issue keys in Jira) → Orchestrator → (keys as prompt) → Architect
Architect → (tech spec as Jira comment) → [Jira] → Designer reads it (if UI story)
Designer → (design spec as Jira comment) → [Jira] → User approves → Developer reads it
Developer → (code in repo + PR link as Jira comment) → [Jira] → Tester reads it
Tester → (test results as Jira comment) → [Jira] → QA reads it
QA → (review as Jira comment) → [Jira] → Bug Fixer reads it (if bugs)
```

For stories without UI components, the Designer step is skipped and the flow goes directly from Architect to Developer.

## Rules for Agents

1. **Read only listed artifacts** — Your prompt lists `Read Artifacts`; read those, not the full thread.
2. **Write exactly one artifact** — Open with `## Summary` (3-5 bullets), then `## Detail`.
3. **Use structured headers** — Follow the templates so downstream agents can find sections.
4. **Include ticket keys** — In commits, PRs, and branch names.
5. **Be specific, not verbose** — File paths, function names, error messages, commit SHAs. Not log dumps.
6. **Reference, don't duplicate** — If it's in the code, link to the file path. If it's in a prior comment, reference that comment's header. Never paste.
