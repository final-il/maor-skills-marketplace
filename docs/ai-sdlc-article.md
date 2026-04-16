# I Built 7 AI Agents That Run a Full Software Development Lifecycle Through Jira

## One command. Seven agents. Thirty Jira tickets. A working product.

---

What if you could type a single command, describe what you want to build, and watch an AI system plan the work, create Jira tickets, design the architecture, write the code, run the tests, review the quality, and fix its own bugs — all while tracking everything in Jira like a real team would?

I built that system. Then I used it to build a real product. Here's what happened.

---

## The Idea: Jira as a Message Bus

Most AI coding tools work in a single loop: you describe something, the AI writes code, you iterate. But real software development isn't a single loop. It's a pipeline — planning, architecture, implementation, testing, QA, bug fixing — with handoffs between different roles at each stage.

I wanted to model that pipeline with AI agents. Not one monolithic agent trying to do everything, but seven specialized agents, each responsible for one phase of the SDLC. The key design decision: **agents don't talk to each other directly.** All coordination flows through Jira.

When the developer agent finishes coding a story, it transitions the ticket to "In Review." The tester agent picks it up because the status changed. If tests fail, a Bug sub-task is created and the story goes back. The QA agent reviews, approves, or rejects. Every decision, every handoff, every piece of context is a Jira ticket, a comment, or a status transition.

Why Jira? Because it gives you auditability for free. Every action is timestamped, attributed, and searchable. When something goes wrong at 2 AM, you can trace exactly what happened, which agent did what, and why.

## The Seven Agents

Each agent is a markdown file with a system prompt, a model assignment, and a set of tools:

| Agent | Model | Job |
|-------|-------|-----|
| **Planner** | Opus | Breaks a project description into epics and stories with acceptance criteria, dependencies, and complexity ratings |
| **Jira Creator** | Sonnet | Creates the tickets in Jira with proper hierarchy, labels, and dependency links |
| **Architect** | Opus | Reads each story, designs the technical approach, posts specs as Jira comments |
| **Developer** | Opus | Creates a branch, writes code, runs linter, commits, opens a PR |
| **Tester** | Sonnet | Writes unit and integration tests, runs them, creates Bug tickets if they fail |
| **QA Reviewer** | Opus | Reviews code against requirements, checks test coverage, approves or rejects |
| **Bug Fixer** | Sonnet | Reads the Bug ticket, reproduces, fixes, re-runs the test suite |

Notice the model split: Opus (stronger reasoning) handles planning, architecture, development, and QA. Sonnet (faster, cheaper) handles the more mechanical work — ticket creation, test writing, bug fixing. This isn't arbitrary — it's a deliberate cost/capability allocation based on where reasoning depth matters most.

## The Human Gate

There's one critical pause point. After the planner produces its epic/story breakdown, the pipeline stops and asks: **"Approve this plan?"**

This isn't optional. The system will not create a single Jira ticket, write a single line of code, or open a single PR until a human reviews and approves the plan. Everything downstream is autonomous, but the direction is human-approved.

## The First Real Test: Building Jiralyzer

Theory is nice. I needed to run it on something real.

**Jiralyzer** is a Jira ticket analytics tool. The problem it solves: Jira's built-in dashboards are too limited for the analytics questions managers actually ask — resolution time distributions, reassignment patterns, cycle time by category, workload distribution across teams.

The input to the pipeline was a plain text description:

> *Build a Jira data export and sync pipeline for jiralyzer. We need a sync CLI command that connects to Jira REST API, fetches tickets with expand=changelog, supports full export and incremental sync, handles pagination, and authenticates via environment variables.*

I typed `/sdlc` followed by that description. Then I watched.

### What the Pipeline Produced

The planner broke the project into **5 epics and 18 stories:**

- **Epic 1: Project Scaffolding** — pyproject.toml, src layout, CLI entry point, test infrastructure, DuckDB schema
- **Epic 2: Parser** — JSON parsing, ticket extraction, changelog/comments/worklogs
- **Epic 3: Database Layer** — JiralyzerDB class, query execution, schema introspection
- **Epic 4: CLI & Visualization** — ingest, query, schema, chart, stats, export commands
- **Epic 5: Claude Code Skill** — SKILL.md, reference docs, marketplace registration

Each story had acceptance criteria, dependencies mapped, and complexity estimated. I reviewed the plan, approved it, and the pipeline took over.

Thirty Jira tickets were created (CSI-4 through CSI-30). The architect posted technical specs on each story. The developer created feature branches, wrote code, and opened PRs. The tester wrote 93 tests. The QA reviewer validated each one.

**Final result:** A working CLI tool with 90% test coverage, 6 DuckDB tables, and a Claude Code skill that lets you ask natural language questions about your Jira data.

## Where It Got Interesting: The Curveballs

A controlled demo where everything works on the first try wouldn't prove much. What proved the system was how it handled things going wrong.

### Curveball 1: The Format Pivot

The original tech specs assumed Jira Server's `entity-engine-xml` export format. When we actually tested against Jira Cloud, the export turned out to be RSS XML — which lacks changelogs and worklogs. Two of our six database tables would be empty.

The pipeline didn't panic. A new story was created: pivot to JSON-only via Jira REST API with `expand=changelog`. The parser stories were re-scoped. One story (CSI-15: ZIP/RSS XML support) was dropped entirely. The pivot happened mid-pipeline, tracked in Jira, with full traceability.

### Curveball 2: API Deprecation

When the sync command first hit Jira's API, it got back a `410 Gone`. Atlassian had deprecated `/rest/api/3/search`. The endpoint that every Jira integration tutorial on the internet uses — gone.

New endpoint discovered: GET `/rest/api/3/search/jql` with `nextPageToken` pagination instead of `startAt` offset pagination. The client was rewritten, tested, and deployed — tracked as a fix within the existing story.

### Curveball 3: Corporate Proxy Breaking Everything

The development environment sits behind a Zscaler TLS inspection proxy. This caused two separate failures:

**SSL certificate rejection:** OpenSSL 3.x has strict CA validation that rejects Zscaler's intermediate certificate ("Basic Constraints of CA cert not marked critical"). The fix: injecting Python's `truststore` library, which delegates SSL verification to the macOS system trust store instead of OpenSSL's cert chain.

**Blank Plotly charts:** Both CDN-loaded and inline-bundled (~4.8MB) Plotly HTML rendered as blank white pages. Likely Zscaler modifying the HTML content during inspection. The fix: defaulting to Matplotlib PNG output, which renders server-side and is immune to proxy interference.

### Curveball 4: The Feedback Loop

This was the real test of the system's design. When we discovered these issues during integration testing, my first instinct was to fix them ad-hoc. But the pipeline is designed for this. Post-release bugs and missing features are supposed to flow back in as new stories.

A new epic was created (CSI-27: Jira Sync Pipeline) with three stories — REST API client, sync CLI command, SKILL.md update. They went through the same pipeline: architect posted specs, developer wrote code, tester wrote tests, QA reviewed. The feedback loop isn't a workaround — it's a first-class feature of the system.

## What I Learned

### 1. Jira as a message bus actually works

I was skeptical that Jira's API would be fast enough and structured enough to serve as inter-agent coordination. It is. The ticket status model maps cleanly to pipeline phases. Comments are a natural place for specs, results, and context. And you get a complete audit trail without building anything custom.

### 2. The model split matters

Using Opus everywhere would be expensive and slow. Using Sonnet everywhere would produce shallow architecture and miss edge cases in code review. The split — Opus for reasoning-heavy phases, Sonnet for execution-heavy phases — gives you quality where it matters and speed where it doesn't.

### 3. The human gate is non-negotiable

Autonomous agents are powerful but opinionated. Without the planning approval gate, the system would happily build the wrong thing very efficiently. One review at the planning stage prevents compounding errors downstream.

### 4. Real-world chaos is the real test

Format pivots, deprecated APIs, corporate proxies, SSL failures — these aren't edge cases. They're what every real project hits. A system that only works in clean environments isn't a system; it's a demo. The feedback loop pattern — where bugs become stories that re-enter the pipeline — is what makes this work in practice.

### 5. Traceability changes everything

Every line of code can be traced back through a PR → a story → an epic → the original plan. Every architectural decision is a Jira comment. Every bug fix references the parent story. When something breaks six months from now, the "why" is in Jira, not in someone's head.

## The Numbers

| | |
|---|---|
| Jira tickets | 30 (5 epics, 25 stories) |
| Automated tests | 93 |
| Code coverage | 90% |
| DuckDB tables | 6 |
| Real tickets ingested | 2,027 |
| Mid-pipeline pivots | 2 (format + API) |
| Stories dropped | 1 (CSI-15, no longer needed) |
| Post-release stories | 4 (CSI-27 through CSI-30) |
| Bug-fix loops | Multiple, all resolved within 3 iterations |

## The Next Challenge: How Do You DevOps an AI System?

With the pipeline working and Jiralyzer in production, I hit a problem I didn't expect: **how do you develop new features for a system that's also your development tool?**

The AI-SDLC pipeline is a Claude Code plugin. Its agents, commands, and skill files ARE the product — markdown files that Claude reads and follows. The marketplace has `autoUpdate: true`, so any push to `main` immediately updates the plugin for all users. There's no build step, no deploy gate. Push equals deploy.

This is fine when things work. It's terrifying when you want to add a web designer agent to the SDLC flow and you're not sure if it'll break the existing pipeline.

### The Naive Approach (and Why It Fails)

My first instinct: feature branches. Work on a `feat/web-designer` branch, test it, merge when ready.

Problem: Claude Code loads plugins from the marketplace's `main` branch. There's no way to tell a test session "use this feature branch." Your plugin instructions are deployed the moment they hit `main`. Feature branches keep your code separate, but your test sessions still run the production plugin.

### The Second Attempt: Duplicate Everything

What if we clone the repos? `maor-skills-marketplace-dev` as a separate GitHub repo, `jiralyzer-dev` as another. Register the dev marketplace alongside the production one. Develop in the `-dev` repos, test there, then copy changes back to production when they work.

We built this. It worked. Then we started finding the edges.

**The SKILL.md problem:** The jiralyzer skill contains hardcoded local paths (`cd /Users/maorb/git/jiralyzer && uv run jiralyzer ...`). The dev version needs to point to `/Users/maorb/git/jiralyzer-dev/`. When you "promote" from dev to prod, you need to `sed` the paths. That's manageable.

**The CLAUDE.md problem:** I started customizing the dev repo's CLAUDE.md — adding "DEV" labels, dev-specific workflow instructions, different "How to Commit" sections. Then I realized: these files ARE the product. They're not config that differs per environment. They're the instructions that define how the system behaves. You can't `sed` "This is the dev marketplace. All new skills are developed and tested here first" back into "Every new skill or agent created in any Claude Code session must be added to this marketplace repo."

Lesson learned: **product files must stay identical between environments.** The only allowed difference is mechanical (a path string), never semantic (different instructions, different labels, different workflow descriptions).

### The Breakthrough: One Repo, Two Branches, One Parameter

While investigating Claude Code's marketplace configuration, we discovered the `ref` parameter:

```json
"maor-skills-marketplace-dev": {
  "source": {
    "source": "git",
    "url": "https://github.com/org/maor-skills-marketplace.git",
    "ref": "dev"
  }
}
```

Same repo. Different branches. Two marketplace entries in settings. No duplicate repos, no sync scripts, no path swapping between repos.

Now the setup is:
- **One marketplace repo** with `main` (production) and `dev` (development) branches
- **Settings** register the same repo twice — once for `main`, once for `dev` via `ref`
- **Project-level settings** in dev directories override which marketplace plugins are active
- **Promotion** is just `git merge dev` into `main`

The SKILL.md path difference (`/jiralyzer/` vs `/jiralyzer-dev/`) lives naturally as a branch-level difference. No scripting needed.

### The Two-Terminal Workflow

The final pattern that emerged:

**Terminal 1 (prod):** Open Claude in `/Users/maorb/git/jiralyzer/`. Global settings load production plugins. Everything works as users expect. Stable.

**Terminal 2 (dev):** Open Claude in `/Users/maorb/git/jiralyzer-dev/`. Project-level settings override global plugins, loading the dev marketplace versions. Experimental changes here don't touch production.

For the marketplace itself (where AI-SDLC agents live), there's no separate directory — just switch to the `dev` branch, make changes, push, test, merge when ready.

### What Doesn't Need Its Own Repo

Not everything needs a dev/prod split. AI-SDLC lives inside the marketplace as a plugin. Its "code" is agent prompts and command definitions — markdown files. There's no local execution, no database, no state. When you improve an agent prompt and push to `main`, every new session gets the update. If the change is bad, you push a fix. The blast radius is low and the recovery time is one commit.

Jiralyzer is different. It has Python code, a DuckDB database, a CLI that runs locally. The dev version needs separate code, a separate database, and a SKILL.md that points to the dev directory. That's what justifies the two-directory setup.

The rule: **if the product runs locally with state, it needs a dev directory. If it's just instructions that Claude reads, branch and merge is enough.**

## What I Learned (Updated)

### 5 (continued). DevOps for AI systems is its own discipline

Traditional DevOps assumes your code is in a repo and your deployment is a separate process. With AI plugin systems, the instructions ARE the code AND the deployment. Push equals deploy. This collapses the usual dev/staging/prod pipeline into something that needs new patterns — like marketplace `ref` parameters and project-level settings overrides.

### 6. Don't over-engineer the dev/prod split

We went through three iterations: feature branches (too simple), duplicate repos (too complex), single repo with branch refs (just right). The temptation to build elaborate infrastructure is strong. But the right answer was a parameter that already existed — we just hadn't looked for it.

### 7. Product files aren't config files

The moment you start adding "DEV" labels and environment-specific instructions to files that define your system's behavior, you've created a merge nightmare. Treat instruction files like code: identical across environments, with only mechanical differences (paths, URLs) that can be maintained as branch-level diffs.

## The Numbers (Updated)

| | |
|---|---|
| Jira tickets | 30 (5 epics, 25 stories) |
| Automated tests | 93 |
| Code coverage | 90% |
| DuckDB tables | 6 |
| Real tickets analyzed | 2,648 (across 3 Jira projects) |
| Mid-pipeline pivots | 2 (format + API) |
| Stories dropped | 1 (CSI-15, no longer needed) |
| Post-release stories | 4 (CSI-27 through CSI-30) |
| Bug-fix loops | Multiple, all resolved within 3 iterations |
| Dev/prod iterations | 3 (branches → dup repos → ref parameter) |
| GitHub repos cleaned up | 4 (eliminated duplicate repos) |

## What's Next

The pipeline is proven on one project. The dev/prod infrastructure is in place. The next step is running the pipeline on different types of projects — infrastructure automation, API services, frontend features — to see where the agent prompts need to generalize and where they're already flexible enough.

The immediate feature on deck: a Metabase-powered interactive dashboard for Jiralyzer, so analytics aren't limited to CLI charts.

The bigger question: can this pattern scale to a team where some agents are AI and some are humans, sharing the same Jira board, the same workflow, the same status transitions? The plumbing is already there. Jira doesn't care who transitions a ticket.

---

*Built with Claude Code, 7 AI agents, a healthy respect for corporate proxies, and three tries to get dev/prod right.*
