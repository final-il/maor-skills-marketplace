# Maor's Skills Marketplace — Project Instructions

## Overview

A Claude Code skills marketplace hosted at `final-il/maor-skills-marketplace`. Users install it via `/plugin` → Marketplace → Add Marketplace → `final-il/maor-skills-marketplace`.

> **⚠️ ai-sdlc moved (2026-08-27).** ai-sdlc is now developed in **`final-csi/csi-marketplace`** (`~/git-dev/csi-marketplace`, `plugins/ai-sdlc/`). The copy in this repo is a **frozen mirror — do not edit it here.** Make all ai-sdlc changes in csi-marketplace (versioned there as `ai-sdlc-vX.Y.Z`; handoffs in its `plugins/ai-sdlc/docs/handoffs/`).

## Repository Structure

```
maor-skills-marketplace/
├── CLAUDE.md                          ← You are here
├── README.md
├── .claude-plugin/
│   └── marketplace.json               ← Marketplace config — lists all plugins
└── plugins/
    ├── aws-secure-architecture/       ← Skill plugin
    │   ├── .claude-plugin/plugin.json
    │   └── skills/aws-secure-architecture/
    │       ├── SKILL.md
    │       └── references/
    ├── technical-docs/                ← Skill plugin
    │   ├── .claude-plugin/plugin.json
    │   └── skills/technical-docs/
    │       ├── SKILL.md
    │       └── references/
    ├── architecture-diagrams/         ← Skill plugin
    │   ├── .claude-plugin/plugin.json
    │   └── skills/architecture-diagrams/
    │       ├── SKILL.md
    │       └── references/
    ├── mac-expert/                    ← Skill plugin
    │   ├── .claude-plugin/plugin.json
    │   └── skills/mac-expert/
    │       └── SKILL.md
    ├── jiralyzer/                     ← Skill plugin
    │   ├── .claude-plugin/plugin.json
    │   └── skills/jiralyzer/
    │       ├── SKILL.md
    │       └── references/
    └── ai-sdlc/                       ← Multi-agent SDLC plugin
        ├── .claude-plugin/plugin.json
        ├── commands/sdlc.md
        ├── agents/
        │   ├── sdlc-planner.md        ← Phase 1: Requirements → epics/stories
        │   ├── sdlc-jira-creator.md   ← Phase 2: Creates Jira tickets
        │   ├── sdlc-architect.md      ← Phase 3: Tech specs per story
        │   ├── sdlc-developer.md      ← Phase 4: Writes code, opens PRs
        │   ├── sdlc-tester.md         ← Phase 5: Writes + runs tests
        │   ├── sdlc-qa-reviewer.md    ← Phase 6: Code review + validation
        │   ├── sdlc-bug-fixer.md      ← Phase 7: Fixes bugs, re-tests
        │   ├── sdlc-lesson-extractor.md ← Self-learning: proposes rule ADDITIONS
        │   ├── sdlc-curator.md        ← Self-learning: proposes rule REMOVALS (inverse of extractor)
        │   └── sdlc-documenter.md     ← Phase 7.7 (opt-in --docs): product docs → README/docs/Confluence
        └── skills/
            ├── sdlc-conventions/       ← Shared Jira conventions + context protocol
            │   ├── SKILL.md
            │   └── references/
            ├── sdlc-handoff/           ← Pause/resume session state capture
            │   └── SKILL.md
            └── sdlc-explainer/         ← Tech-writer: explains the SDLC system with diagrams
                ├── SKILL.md
                └── references/
```

## Skills

| Skill | Purpose |
|-------|---------|
| **aws-secure-architecture** | Design secure AWS architectures with defense-in-depth |
| **technical-docs** | Structured documentation with YAML frontmatter |
| **architecture-diagrams** | Diagrams in Mermaid, PlantUML, Draw.io |
| **mac-expert** | macOS system config, diagnostics, troubleshooting |
| **jiralyzer** | Jira ticket analytics — natural language queries, SQL, charts |

## Plugins

| Plugin | Purpose |
|--------|---------|
| **ai-sdlc** | Multi-agent SDLC automation — plans, creates Jira tickets, architects, codes, tests, QA reviews, fixes bugs |

### AI-SDLC Plugin Details

Entry point: `/sdlc "description"` or `/sdlc /path/to/plan.md` or `/sdlc EPIC-KEY` (resume) or `/sdlc continue {WAVE-ID}` (resume a fast wave)

8 agents coordinate through Jira as a message bus. Each agent transitions tickets through: Backlog → Selected for Development → In Progress → In Review → Testing → Done (with Bug issue type for defect loop). Phase 3.5 (Designer) is optional — runs only for stories with user-facing components, with user approval before development begins. Phase 7.7 (Documenter) is optional too — enabled with `--docs`, it synthesizes durable product docs (README/docs/Confluence) from the epic's specs + merged code after all stories merge.

**Fast mode (`Jira: off`):** Every run the orchestrator offers **fast vs normal** with a one-line recommendation (flags `--fast` / `--normal` pre-answer; `--auto` takes the recommendation). Fast mode **skips only Jira ceremony** during the build — no ticket creation, transitions, comments, or Bug issues — while keeping **every engineering gate** (planner, challenger, architect, designer, integrator, developer, tester incl. smoke + live-process E2E, QA, bug-fixer, Phase 7.5 merge). Coordination moves to the **Fast Work Ledger** (an orchestrator-held git + resume file at `docs/sdlc/_wave-{WAVE-ID}/ledger.md`): work units get synthetic keys `{PROJECT}-F{n}`, agents read requirements from `docs/sdlc/_wave-{WAVE-ID}/plan.md` and return their verdict in return text. This is cheap because the hybrid artifact store already keeps all spec detail in git. **Phase 8.5 (Retro Reconciliation)** is opt-in at wave end: `sdlc-jira-creator` in `Mode: reconcile` back-fills the full QBV → Epic → Story(→ Bug) hierarchy with spec pointers + PR links, each walked to its recorded final status. Full design: `plugins/ai-sdlc/docs/specs/2026-07-19-ai-sdlc-fast-mode-design.md`; conventions in `sdlc-conventions` §2.6.

**Branching model:** Phase 0 auto-detects dev/prod (two-branch) vs single-branch setups. Context block includes `Base Branch` and `PR Target` so agents always branch and open PRs against the correct branch. Phase 8 handles promotion (dev → main) with user approval.

**Codex second opinion (early phases):** In the planning phases only — Phase 0.5 (Research), Phase 1 (Planning), Phase 1.5 (Plan Challenge) — the orchestrator brings **Codex (GPT-5.x)** in as an independent second model via the `codex:codex-rescue` subagent (read-only). Model diversity: Codex critiques the research report, the draft plan, and adversarially attacks the plan; **Claude always owns the artifact** ("consult, Claude reconciles"). On by default; disable with `--no-codex`. Auto-skips gracefully (one log line) if Codex isn't installed/authenticated — never blocks a run. In Phase 1.5 a Codex *critical* finding is binding (LOOPBACK), same weight as a challenger critical; everywhere else it's advisory. Full contract: `sdlc-conventions` → "Codex Consult Protocol"; requires the `codex` plugin (`/codex:setup`).

Agents use Atlassian MCP tools for all Jira operations. Always pass `contentFormat: "markdown"` and `responseContentFormat: "markdown"` on Jira MCP calls.

## IMPORTANT: All Skills and Agents Go Here

**Every new skill or agent created in any Claude Code session must be added to this marketplace repo.** This is the single source of truth for Maor's custom skills — **except `ai-sdlc`, which is now developed in `final-csi/csi-marketplace`** (the copy here is a frozen mirror). After adding a skill:
1. Follow the steps below to register it
2. Commit and push to `final-il/maor-skills-marketplace`
3. Install via the marketplace to verify the marketplace config is correct and the skill works

This applies whether working inside this repo or from any other directory.

## How to Add a New Skill

Each skill is its own plugin under `plugins/`. This prevents cross-registration of skills across plugin namespaces.

1. Create `plugins/<skill-name>/.claude-plugin/plugin.json`:
   ```json
   {
     "name": "skill-name",
     "description": "What the skill does",
     "author": { "name": "Maor B", "email": "maorb@final.co.il" }
   }
   ```
2. Create `plugins/<skill-name>/skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
3. Add optional `references/` directory for detailed guidance files
4. Update `.claude-plugin/marketplace.json` — add a new entry to the `plugins` array:
   ```json
   {
     "name": "skill-name",
     "description": "What the skill does",
     "source": "./plugins/skill-name",
     "strict": false
   }
   ```
5. Update `README.md` with the new skill in the table
6. Commit and push
7. Install via marketplace: run `/plugin` → select "Browse and install plugins" → select `maor-skills-marketplace` → install the new skill
8. Run `/reload-plugins` to activate

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
