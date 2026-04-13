# AI-SDLC Context Protocol

## How Agents Share Context

Agents run in complete isolation — each agent starts with a fresh context window and no memory of previous agents. All context must be explicitly passed or stored in persistent systems.

## Three Context Channels

### Channel 1: Agent Prompt (Structural Metadata)

The orchestrator passes a standardized context block to every agent:

```
## SDLC Context
- Project Key: {projectKey}
- Cloud ID: {cloudId}
- Repo Path: {absolute_path_to_project_repo}
- Base Branch: {main_branch_name}
- Issue Keys: {comma-separated list of relevant Jira issue keys}
- Transition Map: To Do={id}, Planning={id}, Ready for Dev={id}, In Progress={id}, In Review={id}, Testing={id}, Done={id}, Bug={id}
```

This block is injected into the agent's spawn prompt. It provides the structural information agents need to interact with Jira and the codebase.

### Channel 2: Jira Tickets (Primary Content Channel)

This is the **primary** channel for substantive context:

- **Story descriptions** contain requirements and acceptance criteria
- **Comments** contain tech specs, implementation notes, test results, QA findings
- **Status** indicates where in the pipeline a ticket is
- **Sub-tasks** (Bug type) contain bug reports

**Reading context from Jira:**
```
1. Use getJiraIssue with the ticket key to read description + fields
2. Comments are included in the response (most recent first)
3. Parse the structured comment format to find the relevant section
```

**Writing context to Jira:**
```
1. Use addCommentToJiraIssue with contentFormat: "markdown"
2. Follow the comment templates in ticket-templates.md
3. Use structured headers (## Tech Spec, ## Test Results, etc.) so downstream agents can find sections
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
Architect → (tech spec as Jira comment) → [Jira] → Developer reads it
Developer → (code in repo + PR link as Jira comment) → [Jira] → Tester reads it
Tester → (test results as Jira comment) → [Jira] → QA reads it
QA → (review as Jira comment) → [Jira] → Bug Fixer reads it (if bugs)
```

## Rules for Agents

1. **Never assume context** — Always read from Jira before acting
2. **Always write back** — Post your results so the next agent has what it needs
3. **Use structured comments** — Follow the templates so downstream agents can parse them
4. **Include ticket keys** — In commits, PRs, and branch names
5. **Be explicit** — When writing to Jira, include file paths, function names, error messages — anything the next agent needs
6. **Don't duplicate** — If something is in the code, reference the file path instead of copying it into Jira
