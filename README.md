# Maor's Skills Marketplace

A collection of custom skills, agents, and plugins for Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| [aws-secure-architecture](plugins/aws-secure-architecture/) | Design secure AWS architectures with defense-in-depth — private connectivity, egress control, multi-account security, and zero-trust patterns |
| [technical-docs](plugins/technical-docs/) | Generate structured technical documentation — architecture docs, runbooks, ADRs, API docs, postmortems, security reviews |
| [architecture-diagrams](plugins/architecture-diagrams/) | Generate architecture diagrams in Mermaid, PlantUML, and Draw.io formats |
| [mac-expert](plugins/mac-expert/) | Apple macOS expert — system config, diagnostics, shell, networking, Homebrew, security, performance, troubleshooting |
| [csi-discovery](plugins/csi-discovery/) | CSI Department discovery agent — maps teams' systems, processes, tooling, and pain points through structured forms, source scanning, and Confluence integration |
| [jira-sync-internal](plugins/jira-sync-internal/) | Air-gapped Jira sync — internal (offline) side. Query the local SQLite mirror, make offline edits/comments/transitions/creates, ingest packages from external, export deltas |
| [jira-sync-external](plugins/jira-sync-external/) | Air-gapped Jira sync — external (online) side. Pull from Jira Cloud, query local store, ingest internal packages, push deltas to Jira Cloud, export packages |

## Plugins

| Plugin | Description |
|--------|-------------|
| [ai-sdlc](plugins/ai-sdlc/) | AI-powered software development lifecycle — plans projects, creates Jira tickets, designs architecture, writes code, tests, reviews, and fixes bugs through 7 coordinated agents |

### AI-SDLC Agents

| Agent | Role | Model |
|-------|------|-------|
| sdlc-planner | Breaks projects into epics/stories with acceptance criteria | opus |
| sdlc-jira-creator | Creates Jira tickets with hierarchy and links | sonnet |
| sdlc-architect | Designs technical specs per story | opus |
| sdlc-designer | UI/UX design specs — layouts, colors, wireframes (optional, user-facing stories only) | opus |
| sdlc-developer | Implements code, commits, opens PRs | opus |
| sdlc-tester | Writes and runs tests | sonnet |
| sdlc-qa-reviewer | Reviews code quality and requirement compliance | opus |
| sdlc-bug-fixer | Fixes bugs found by tester/QA | sonnet |

### AI-SDLC Skills

| Skill | Purpose |
|-------|---------|
| sdlc-conventions | Shared Jira conventions, workflow states, artifact discipline, and context protocol used by all agents |
| sdlc-handoff | Capture session state for rich pause/resume of a pipeline run |
| sdlc-explainer | Technical writer for the AI-SDLC system — explains the idea, pipeline flow, agent coordination, and decision-making with mind maps, flowcharts, sequence and state diagrams. Derives the current system shape from source, so it stays accurate as the pipeline evolves |

**Usage:** `/sdlc "project description"` or `/sdlc /path/to/plan.md` or `/sdlc EPIC-KEY` (resume)

**Branching:** Auto-detects dev/prod model (dev + main branches) or single-branch. PRs target the correct branch automatically. Promotion (dev → main) offered at completion with user approval.

## Structure

- `plugins/` — All plugins (both skill-only and multi-component) with their own `.claude-plugin/plugin.json`, skills, agents, and commands
