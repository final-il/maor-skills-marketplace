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

Tickets flow through these statuses:

```
To Do → Planning → Ready for Dev → In Progress → In Review → Testing → Done
                                                       ↘ Bug → In Progress (loop)
```

See `references/workflow-states.md` for detailed status definitions.

## Labels

All tickets created by the AI-SDLC system carry these labels:
- `ai-sdlc` — identifies tickets created/managed by the pipeline
- `phase-N` — the delivery phase (e.g., `phase-1a`, `phase-1b`)

## Ticket Structure

The system creates tickets in this hierarchy:
- **Epic** — Major functional area (e.g., "Core Engine", "Visualization")
- **Story** — Implementable unit (1-3 days of work)
- **Sub-task** — Optional fine-grained steps
- **Bug** — Created as sub-task of a Story when tests/QA fail

See `references/ticket-templates.md` for description templates.

## Context Protocol

Agents run in isolation. They share context through three channels:

1. **Agent prompt** — Structural metadata (cloudId, projectKey, repo path, issue keys, transition map)
2. **Jira tickets** — Primary channel. Requirements, tech specs, test results, bug reports (descriptions + comments)
3. **Project repo** — Code, CLAUDE.md, config files

See `references/context-protocol.md` for the full specification.

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

## Agent Workflow Rules

1. **Always read from Jira first** — Get the ticket's current state before acting
2. **Always write back to Jira** — Post results as comments so the next agent has context
3. **Use markdown in Jira** — Set `contentFormat: "markdown"` and `responseContentFormat: "markdown"` on all MCP calls
4. **Transition tickets** — Move tickets to the correct status when done
5. **Create Bug sub-tasks** — When tests fail or QA finds issues, create a Bug sub-task under the parent Story
6. **Commit messages** — Always include the Jira ticket key: `{STORY-KEY}: {summary}`
7. **Branch naming** — Use `{story-key}/{short-slug}` (e.g., `PROJ-42/xml-parser`)
8. **PR target** — Always use `--base {pr_target_branch}` when creating PRs
