# Maor's Skills Marketplace — Project Instructions

## Overview

A Claude Code skills marketplace hosted at `final-il/maor-skills-marketplace`. Users install it via `/plugin` → Marketplace → Add Marketplace → `final-il/maor-skills-marketplace`.

## Repository Structure

```
maor-skills-marketplace/
├── CLAUDE.md                          ← You are here
├── README.md
├── .claude-plugin/
│   └── marketplace.json               ← Marketplace config — lists all plugins/skills
├── skills/
│   ├── aws-secure-architecture/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── private-to-saas.md
│   │       ├── multi-account-network.md
│   │       └── zero-trust-service-mesh.md
│   ├── technical-docs/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── architecture.md, runbook.md, adr.md
│   │       ├── api-docs.md, postmortem.md
│   │       └── security-review.md
│   ├── architecture-diagrams/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── flowchart.md, sequence.md
│   │       └── cloud-infra.md
│   └── mac-expert/
│       └── SKILL.md
└── plugins/
    └── ai-sdlc/                       ← Multi-agent SDLC automation plugin
        ├── .claude-plugin/
        │   └── plugin.json
        ├── commands/
        │   └── sdlc.md                ← Orchestrator entry point (/sdlc)
        ├── agents/
        │   ├── sdlc-planner.md        ← Phase 1: Requirements → epics/stories (opus)
        │   ├── sdlc-jira-creator.md   ← Phase 2: Creates Jira tickets (sonnet)
        │   ├── sdlc-architect.md      ← Phase 3: Tech specs per story (opus)
        │   ├── sdlc-developer.md      ← Phase 4: Writes code, opens PRs (opus)
        │   ├── sdlc-tester.md         ← Phase 5: Writes + runs tests (sonnet)
        │   ├── sdlc-qa-reviewer.md    ← Phase 6: Code review + validation (opus)
        │   └── sdlc-bug-fixer.md      ← Phase 7: Fixes bugs, re-tests (sonnet)
        └── skills/
            └── sdlc-conventions/
                ├── SKILL.md           ← Jira conventions, ticket templates
                └── references/
                    ├── workflow-states.md
                    ├── ticket-templates.md
                    └── context-protocol.md
```

## Skills

| Skill | Purpose |
|-------|---------|
| **aws-secure-architecture** | Design secure AWS architectures with defense-in-depth |
| **technical-docs** | Structured documentation with YAML frontmatter |
| **architecture-diagrams** | Diagrams in Mermaid, PlantUML, Draw.io |
| **mac-expert** | macOS system config, diagnostics, troubleshooting |

## Plugins

| Plugin | Purpose |
|--------|---------|
| **ai-sdlc** | Multi-agent SDLC automation — plans, creates Jira tickets, architects, codes, tests, QA reviews, fixes bugs |

### AI-SDLC Plugin Details

Entry point: `/sdlc "description"` or `/sdlc /path/to/plan.md` or `/sdlc EPIC-KEY` (resume)

7 agents coordinate through Jira as a message bus. Each agent transitions tickets through: Backlog → Selected for Development → In Progress → In Review → Testing → Done (with Bug issue type for defect loop).

Agents use Atlassian MCP tools for all Jira operations. Always pass `contentFormat: "markdown"` and `responseContentFormat: "markdown"` on Jira MCP calls.

## IMPORTANT: All Skills and Agents Go Here

**Every new skill or agent created in any Claude Code session must be added to this marketplace repo.** This is the single source of truth for Maor's custom skills. After adding a skill:
1. Follow the steps below to register it
2. Commit and push to `final-il/maor-skills-marketplace`
3. Install via the marketplace to verify the marketplace config is correct and the skill works

This applies whether working inside this repo or from any other directory.

## How to Add a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add optional `references/` directory for detailed guidance files
3. Update `.claude-plugin/marketplace.json` — add a new entry to the `plugins` array:
   ```json
   {
     "name": "skill-name",
     "description": "What the skill does",
     "source": "./",
     "strict": false,
     "skills": ["./skills/skill-name"]
   }
   ```
4. Update `README.md` with the new skill in the table
5. Commit and push
6. Install via marketplace: run `/plugin` → select "Browse and install plugins" → select `maor-skills-marketplace` → install the new skill
7. Run `/reload-plugins` to activate

## How to Add a New Plugin

Plugins go under `plugins/<plugin-name>/` with their own `.claude-plugin/plugin.json`. They can contain agents, commands, and skills.

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json`
2. Add agents under `plugins/<plugin-name>/agents/`
3. Add commands under `plugins/<plugin-name>/commands/`
4. Add skills under `plugins/<plugin-name>/skills/`
5. Register in `.claude-plugin/marketplace.json` with `"source": "./plugins/<plugin-name>"`
6. Update `README.md`
7. Commit, push, install via marketplace

## Skill Writing Guide

- **SKILL.md** — Keep under 500 lines. Include YAML frontmatter with `name` and `description`. The description is the primary triggering mechanism — make it specific and slightly "pushy" to avoid under-triggering.
- **references/** — Detailed guidance loaded on demand. Use for templates, patterns, and examples that would bloat the main SKILL.md.
- **Description format** — Include both what the skill does AND specific trigger phrases. Example: "Design secure AWS architectures... Also trigger when the user mentions air-gapped accounts, private endpoints... even if they don't explicitly say 'architecture design.'"

## Design Decisions

- Skills are designed to chain: `aws-secure-architecture` → `architecture-diagrams` → `technical-docs` → docx/pptx/pdf (from Anthropic marketplace)
- `technical-docs` outputs markdown with YAML frontmatter so downstream skills (docx, pptx) know which template to apply
- PlantUML AWS stdlib (`!include <awslib/...>`) is unreliable — the `architecture-diagrams` skill includes both stdlib and plain PlantUML examples as fallback
