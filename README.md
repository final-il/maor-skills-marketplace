# Maor's Skills Marketplace

A collection of custom skills, agents, and plugins for Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| [aws-secure-architecture](skills/aws-secure-architecture/) | Design secure AWS architectures with defense-in-depth — private connectivity, egress control, multi-account security, and zero-trust patterns |
| [technical-docs](skills/technical-docs/) | Generate structured technical documentation — architecture docs, runbooks, ADRs, API docs, postmortems, security reviews |
| [architecture-diagrams](skills/architecture-diagrams/) | Generate architecture diagrams in Mermaid, PlantUML, and Draw.io formats |
| [mac-expert](skills/mac-expert/) | Apple macOS expert — system config, diagnostics, shell, networking, Homebrew, security, performance, troubleshooting |

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
| sdlc-developer | Implements code, commits, opens PRs | opus |
| sdlc-tester | Writes and runs tests | sonnet |
| sdlc-qa-reviewer | Reviews code quality and requirement compliance | opus |
| sdlc-bug-fixer | Fixes bugs found by tester/QA | sonnet |

**Usage:** `/sdlc "project description"` or `/sdlc /path/to/plan.md`

## Structure

- `skills/` — Individual skills with `SKILL.md` and optional `references/`
- `plugins/` — Multi-component plugins with agents, commands, and skills
