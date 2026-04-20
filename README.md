# Maor's Skills Marketplace

A collection of custom skills, agents, and plugins for Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| [aws-secure-architecture](plugins/aws-secure-architecture/) | Design secure AWS architectures with defense-in-depth — private connectivity, egress control, multi-account security, and zero-trust patterns |
| [technical-docs](plugins/technical-docs/) | Generate structured technical documentation — architecture docs, runbooks, ADRs, API docs, postmortems, security reviews |
| [architecture-diagrams](plugins/architecture-diagrams/) | Generate architecture diagrams in Mermaid, PlantUML, and Draw.io formats |
| [mac-expert](plugins/mac-expert/) | Apple macOS expert — system config, diagnostics, shell, networking, Homebrew, security, performance, troubleshooting |
| [jiralyzer](plugins/jiralyzer/) | Jira ticket analytics — natural language queries, SQL generation, DuckDB, interactive Plotly charts |

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

**Usage:** `/sdlc "project description"` or `/sdlc /path/to/plan.md` or `/sdlc EPIC-KEY` (resume)

**Branching:** Auto-detects dev/prod model (dev + main branches) or single-branch. PRs target the correct branch automatically. Promotion (dev → main) offered at completion with user approval.

## Structure

- `plugins/` — All plugins (both skill-only and multi-component) with their own `.claude-plugin/plugin.json`, skills, agents, and commands
