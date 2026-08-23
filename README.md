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
| [ai-sdlc](plugins/ai-sdlc/) | AI-powered software development lifecycle — researches, plans, challenges the plan, creates Jira tickets, designs architecture, audits cross-story integration, writes code, tests, reviews, fixes bugs, merges PRs, and documents through 16 coordinated agents |

### AI-SDLC Agents

| Agent | Role | Model |
|-------|------|-------|
| sdlc-researcher | Surveys OSS landscape for build-vs-buy before planning | opus |
| sdlc-planner | Breaks projects into epics/stories with acceptance criteria | opus |
| sdlc-plan-challenger | Adversarially stress-tests the plan before user approval | opus |
| sdlc-jira-creator | Creates Jira tickets with hierarchy and links (also retro reconciliation) | sonnet |
| sdlc-architect | Designs technical specs per story (two-pass: lead ownership registry + parallel detail) | opus |
| sdlc-designer | UI/UX design specs — layouts, colors, wireframes (optional, user-facing stories only) | opus |
| sdlc-integrator | Audits cross-story name/file collisions before development | sonnet |
| sdlc-developer | Implements code, commits, opens PRs | opus |
| sdlc-tester | Writes and runs tests, incl. smoke-path + live-process E2E | sonnet |
| sdlc-qa-reviewer | Reviews code quality and requirement compliance | opus |
| sdlc-bug-fixer | Fixes bugs found by tester/QA | sonnet |
| sdlc-conflict-resolver | Union-merges additive multi-PR conflicts during continuous merge | sonnet |
| sdlc-documenter | Synthesizes product docs (README/docs/Confluence) after merge (`--docs`) | sonnet |
| sdlc-jira-reader | Reads/summarizes Jira for the orchestrator without bloating its context | sonnet |
| sdlc-lesson-extractor | Proposes rule additions from corrections + agent self-reports (self-learning) | sonnet |
| sdlc-curator | Proposes rule removals/consolidations — subtractive inverse of the extractor | sonnet |

### AI-SDLC Skills

| Skill | Purpose |
|-------|---------|
| sdlc-conventions | Shared Jira conventions, workflow states, artifact discipline, and context protocol used by all agents |
| sdlc-handoff | Capture session state for rich pause/resume of a pipeline run |
| sdlc-explainer | Technical writer for the AI-SDLC system — explains the idea, pipeline flow, agent coordination, and decision-making with mind maps, flowcharts, sequence and state diagrams. Derives the current system shape from source, so it stays accurate as the pipeline evolves |

**Usage:** `/sdlc "project description"` or `/sdlc /path/to/plan.md` or `/sdlc EPIC-KEY` (resume) or `/sdlc continue {WAVE-ID}` (resume a fast wave)

**Flags:** `--auto` (auto-approve all gates) · `--docs` (synthesize product docs after merge) · `--fast` / `--normal` (pre-answer the fast-vs-normal mode gate)

**Fast mode:** Every run offers **fast vs normal** with a recommendation. Fast mode skips only Jira ceremony during the build (no tickets, transitions, comments, or Bug issues) while keeping every engineering gate — tests, smoke + live-process E2E, QA, and PR merge all run identically. Coordination moves to a git-backed **Fast Work Ledger** (`docs/sdlc/_wave-{WAVE-ID}/`); work units use synthetic `{PROJECT}-F{n}` keys. At wave end, opt-in **retro reconciliation** back-fills the full Jira QBV → Epic → Story(→ Bug) hierarchy with spec pointers, PR links, and final statuses.

**Branching:** Auto-detects dev/prod model (dev + main branches) or single-branch. PRs target the correct branch automatically. Promotion (dev → main) offered at completion with user approval.

## Structure

- `plugins/` — All plugins (both skill-only and multi-component) with their own `.claude-plugin/plugin.json`, skills, agents, and commands
