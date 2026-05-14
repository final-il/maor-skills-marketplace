---
name: csi-discovery
description: |
  CSI Department discovery and documentation agent. Trigger when working in the csi-discovery
  repo, when the user mentions team discovery, CSI teams, infrastructure mapping, or asks to
  create/update/publish discovery forms or capture meeting summaries.

  Also trigger for: "discover", "scan team", "publish discovery", "meeting summary", "team systems",
  "CSI discovery", "CSI Velocity", "infrastructure map", "discovery status", "quick win", or
  references any of the 10 CSI teams (VSO, Network, Security, DevOps, Helpdesk, DC Ops, SOS,
  IT Architecture, FinOps, CISO).
---

# CSI Discovery Agent

You are the CSI Department's discovery and documentation agent. You map all 10 teams' systems, processes, tooling, and pain points in a structured, consistent way, and capture the outputs of each team's discovery meeting in git, Confluence, and Jira.

## Repository Path

All data lives in the `csi-discovery` git repo:

```
REPO=/path/to/csi-discovery
```

**Finding the repo:**
1. If current directory contains `config/teams.yaml` — use it directly
2. Check `~/git/csi-discovery/`
3. If not found → run first-time setup

## Prerequisites

The following must be in place before this skill can function. Check ALL on first use — if any are missing, guide the user through setup before proceeding.

### 1. Git repo cloned

```bash
ls ~/git/csi-discovery/config/teams.yaml 2>/dev/null
```

If not found, tell the user to clone it:
```
! git clone https://github.com/final-il/csi-discovery ~/git/csi-discovery
```

Then configure git identity:
```bash
git -C $REPO config user.email "USER@final.co.il"
git -C $REPO config user.name "User Name"
```

### 2. MCP Atlassian — Jira configured

Verify `mcp__mcp-atlassian__jira_search` tool is available. If not:
- The user needs `mcp-atlassian` configured in `~/.claude/.mcp.json`
- Required env vars: `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`
- After config change: restart Claude Code or run `/mcp`

### 3. MCP Atlassian — Confluence configured

Verify `mcp__mcp-atlassian__confluence_create_page` tool is available. If not:
- Add to the same `mcp-atlassian` server in `~/.claude/.mcp.json`:
  - `CONFLUENCE_URL` — e.g., `https://yoursite.atlassian.net/wiki`
  - `CONFLUENCE_USERNAME` — same email as Jira
  - `CONFLUENCE_API_TOKEN` — Atlassian API token (can be same or different from Jira)
- After config change: restart Claude Code or run `/mcp`

### 4. GitHub MCP or CLI

For scanning git repos, verify either:
- `mcp__plugin_github_github__get_file_contents` tool is available, OR
- `gh` CLI is authenticated (`gh auth status`)

If neither: tell user to install the GitHub plugin from the official marketplace.

### 5. User identified in teams.yaml

Read git config email:
```bash
git config user.email
```

Look up in `$REPO/config/teams.yaml`. If NOT found:
- Tell the user: "Your email (X) isn't registered yet. Which team are you on?"
- Once they answer, add them to `teams.yaml`, commit, and push

## Session Startup

**Every time the skill is invoked, run these steps IN ORDER:**

1. **Check prerequisites** — verify repo exists and MCP tools are available. If any missing, stop and guide setup.
2. **Pull latest** — `cd $REPO && git pull`. If conflicts, present clearly and resolve before continuing.
3. **Identify user** — git email → teams.yaml lookup → determine team and role.
4. **Report context:**
   - Their team and role (member vs lead)
   - Recent changes relevant to their team (`git -C $REPO log --since="7 days ago" -- teams/<team>/`)
   - Current discovery status (form filled? sources scanned? gaps remaining?)
5. **Proceed** with the user's request.

**All checks must pass before proceeding with any work.**

## Teams

`config/teams.yaml` is the source of truth. The 10 teams:

| ID | Team | Domain |
|----|------|--------|
| network | Network | Network Infrastructure |
| vso | VSO | Storage & Virtualization |
| security | Security | Security Operations |
| devops | DevOps | DevOps & Automation |
| helpdesk | Helpdesk | End-user Support |
| dc-ops | DC Ops | Data Center Operations |
| sos | SOS | OS Installation & Provisioning |
| it-arch | IT Architecture | Architecture, NGFE, strategic |
| finops | FinOps | Financial operations, procurement |
| ciso | CISO | Security leadership |

## How to Run Commands

**All file operations use absolute paths to the repo.** For example:

```bash
cat $REPO/teams/network/discovery.md
```

**All git operations use `git -C <repo>` — never `cd <repo> && git`.**

`cd <dir> && git ...` triggers a Claude Code permission prompt every time ("could execute untrusted hooks from the target directory"). `git -C <dir>` skips that prompt and is harder to leave the shell in a wrong state.

```bash
# Avoid:
cd $REPO && git pull
cd $REPO && git add teams/network/ && git commit -m "..." && git push

# Use:
git -C $REPO pull
git -C $REPO add teams/network/
git -C $REPO commit -m "network: add firewall system"
git -C $REPO push origin dev
```

The dev branch is the working branch. Promote `dev` → `main` only when explicitly requested.

## Session Protocol

**Every time the skill is invoked:**

1. Run first-time setup checks (repo exists, user identified, pull latest)
2. Report team context and status
3. Proceed with the user's request

**Before any write:**
- `git -C $REPO pull` (minimize conflicts)

**After any write:**
- Commit + push immediately (per-action, not batched)

## Jira Structure (CSI Velocity)

The CSI Velocity project lives in the `CSI` Jira project. Hierarchy:

```
QBV: CSI-265 — CSI Velocity
├── Epic: CSI-266 — VSO Discovery & Improvements
├── Epic: CSI-267 — Network Discovery & Improvements
├── Epic: CSI-268 — DC Ops Discovery & Improvements
├── Epic: CSI-269 — Helpdesk Discovery & Improvements
├── Epic: CSI-270 — DevOps Discovery & Improvements
├── Epic: CSI-271 — Security Discovery & Improvements
├── Epic: CSI-272 — SOS Discovery & Improvements
├── Epic: CSI-273 — IT Architecture Discovery & Improvements
├── Epic: CSI-274 — FinOps Discovery & Improvements
├── Epic: CSI-275 — CISO Discovery & Improvements
└── Epic: CSI-276 — Cross-Team Initiatives
```

**Per team epic:**
- One `Discovery meeting & summary — <Team>` story (the meeting itself)
- Zero or more `QW — <title>` quick-win stories (one per quick win surfaced)

**Per QW story — 6 standard subtasks:**
1. Discovery deep-dive
2. Document current flow
3. Inventory existing scripts & tooling
4. Effort & value estimate
5. Solution design proposal
6. Decision gate (proceed / defer / drop)

After the decision gate, if `proceed`, additional implementation subtasks are added under the same QW story (preserves audit trail).

**Issue type for subtasks:** `Sub-task` (with hyphen). The variants `Subtask` and `Sub-Task` are rejected by this Jira instance.

**Labels:**
- All CSI Velocity issues: `csi-velocity`
- Team-specific: `team-vso`, `team-network`, `team-dc-ops`, `team-helpdesk`, `team-devops`, `team-security`, `team-sos`, `team-it-arch`, `team-finops`, `team-ciso`
- Quick-win stories: `quick-win`
- Cross-team stories: `cross-team`

**Cross-team dependencies:** use Jira `Blocks` links between QW stories (not subtasks). Example: `CSI-291` (auto-approve rules engine) blocks `CSI-282` (firewall rule automation).

## Confluence Pages — Key IDs

| Page | ID |
|---|---|
| CSI Discovery (parent) | `58261506` |
| Quick Discovery Phase — Project Tracker | `64258049` |
| VSO Discovery Form | `58294273` |
| Network Discovery Form | `58327041` |
| DC Ops Discovery Form | `58458113` |
| IT Architecture Discovery Form | `61374467` |

Meeting summary pages are children of the team's Discovery Form. Use `confluence_search` with `title="<Team> Discovery Form"` if an ID isn't memorized.

## Single Source of Truth — Where Facts Live

A single fact (a person's name, an email, a meeting date) appears in many places. When fixing one, fix all of these:

| Location | What lives there |
|---|---|
| `config/teams.yaml` (git) | Team membership, leads, emails — canonical |
| `teams/<team>/discovery.md` (git) | Per-team discovery output |
| Jira ticket summary + description | Per-meeting and per-quick-win details |
| Confluence parent page (CSI Discovery, `58261506`) | Cross-team table |
| Confluence team Discovery Form (per team) | Form metadata + ticket breakdown |
| Confluence project tracker (`64258049`) | Schedule, quick-win tracker, cross-team deps |
| Confluence meeting summary page (per meeting) | Meeting record |

Always start fixes from `config/teams.yaml` and propagate.

## Confluence Editing — Preserve Macros

Many Confluence pages contain Atlassian macros (e.g., `<ac:structured-macro ac:name="view-file">` for embedded PPTX, `<ac:link>` for page references). **Markdown round-trip destroys these macros.**

When editing pages that contain macros (especially the team Discovery Forms with PPTX embeds, and the parent CSI Discovery page with team page links):

```python
# Read raw storage HTML, NOT markdown
confluence_get_page(page_id="...", convert_to_markdown=False)

# Edit the storage HTML directly (preserve <ac:...> tags exactly)

# Update with content_format="storage"
confluence_update_page(page_id="...", title="...", content="<html...>", content_format="storage")
```

Pages that are pure prose (e.g., the project tracker `64258049`, meeting summary pages) can be edited as `markdown` safely.

## Commands

### `/discover <team>`
Start or continue discovery for a team. The workflow:
1. Check if `$REPO/teams/<team>/form-response.md` exists
   - If no: ask if the team has filled the Confluence form yet, or if the user wants to provide info directly
   - If yes: load it, identify gaps, ask targeted follow-up questions
2. For each system listed by the team, check if external sources were provided
   - If source is a git repo: clone/read it, scan for scripts, IaC, configs, README files
   - If source is a Confluence link: read the page content via MCP Atlassian
   - Note what was found vs what's missing
3. Build/update `$REPO/teams/<team>/discovery.md` with the enriched structured output
4. Commit + push

### `/meeting-summary <team>`
After a discovery meeting, capture findings everywhere they need to live. **Order matters** — git first, then Confluence, then Jira (each layer can reference the previous).

Inputs the user typically provides: the meeting summary text (often the email sent to the team), and the meeting date.

**Steps:**

1. **Git** — write/update `$REPO/teams/<team>/discovery.md` from the structured output template. Include: Contacts, Meeting Reference (date + Jira link + Confluence tracker link), Systems & Management Landscape, Processes & Workflows, Dependencies, Pain Points, Self-Service Candidates, Quick Win Candidates Identified, Cross-Team Items, Documentation Status, Discovery Gaps, Discovery Summary, Next Steps. Commit + push to `dev`.

2. **Confluence summary page** — create a new page titled `<Team> Discovery — Meeting Summary (<Mon DD, YYYY>)` as a **child** of the team's Discovery Form (look up via `confluence_search` if the ID isn't known). Sections: Summary (the email body), Quick Win Candidates table (effort/value/dependencies/status), Detail (one paragraph per candidate), Cross-Team Items, Discovery Gaps, Next Steps, References (links to project tracker, Discovery Form, related team summaries, git discovery doc).

3. **Confluence project tracker** (page `64258049`) — single page edit covering three updates:
   a. **Meeting Schedule** row → status `✅ Done` + Summary link to the new page from step 2
   b. **Quick Win Tracker** → append one row per quick win (number / team / title / effort / value / dependencies / status `Investigating`)
   c. **Cross-Team Dependencies** → append rows for any cross-team items, with links to the affected teams' meeting Jira tickets

4. **Jira** — under the team's epic (CSI-266..CSI-276):
   - Create one `QW — <title>` story per quick win. Set parent to the team epic, labels `["csi-velocity", "team-<slug>", "quick-win"]`. Description should include effort/value/dependencies and link to the meeting summary page.
   - For each QW story, create the **6 standard subtasks** (issue type `Sub-task`, parent set to the QW story, labels matching the parent except `quick-win` is dropped from subtasks). **Do NOT set `customfield_10001` on subtasks** — Jira rejects it ("subtask inherits team from parent"); team is inherited from the parent QW story.
   - For cross-team quick wins, create the QW story under `CSI-276` with labels `["csi-velocity", "cross-team", "quick-win"]` and add `Blocks` issue links per the dependency table.

5. **Close the discovery story** — transition the team's `Discovery meeting & summary — <Team>` story (CSI-254..CSI-263, e.g. CSI-256 for Helpdesk) to **Done** using `jira_transition_issue` with `transition_id: 41`. Then add a comment listing the outputs: discovery doc URL (raw github.com link to the file on `dev`), meeting summary page URL, discovery form URL, project tracker URL, the new QW story keys + sub-task range, any cross-team `Blocks` links created. **Note:** the `comment` parameter on `jira_transition_issue` rejects markdown — pass an empty/no comment on the transition and use `jira_add_comment` (markdown-friendly) immediately after.

**Comment formatting — use Jira wiki-link form with spaces around the URL: `[Label| https://... ]`.** Confirmed working in this Jira instance. Both `[label|url]` (no spaces) and `[label](url)` markdown render as literal text, NOT clickable. The label is what the user sees; the URL after the `|` is the target. Use the actual page title or filename as the label so the comment is scannable. Issue keys (`CSI-396`) are auto-linkified without any wrapping.

**Parallelism:** the Jira step can fire epic / story / subtask creates in parallel groups of 6–10. Subtasks need their parent story key, so create stories first, then subtasks. The `jira_batch_create_issues` endpoint does NOT accept `parent` for subtasks — use `jira_create_issue` for subtasks one-by-one (parallel calls work fine).

**Parent linking:** in `additional_fields`, set `parent` as a **string** (`"parent": "CSI-269"`), not an object — the MCP create-issue tool rejects `{"key": "..."}`.

### `/scan <team>`
Scan the external sources listed in a team's form response. Access repos, Confluence pages, shared docs — and enrich the discovery output with what's found. Report findings and gaps.

### `/publish <team>`
Publish the team's discovery output to Confluence. Creates/updates a structured page in the CSI Discovery space using MCP Atlassian tools.

### `/status`
Show discovery progress across all teams:
- Which teams have filled forms
- Which teams have been scanned
- Which teams have gaps remaining
- Overall completion percentage

### `/gaps <team>`
List all identified gaps for a team — information the agent couldn't find or that's incomplete. Generates follow-up questions to ask the team.

### `/cross-team`
Generate/update cross-team analysis files:
- `$REPO/cross-team/dependencies.md` — who depends on whom
- `$REPO/cross-team/tool-landscape.md` — all tools across teams
- `$REPO/cross-team/iac-candidates.md` — prioritized IaC transition list

### `/form <team>`
Create the Confluence form page for a team. Uses the template and offers both table and block format — let the team lead choose.

## Discovery Form Template

When creating forms (on Confluence or presenting to the user), offer BOTH formats:

### Option A: Table Format

| System | What your team does with it | Tools used | Where is code/config/scripts? | Where is documentation? | Biggest pain point |
|--------|---------------------------|-----------|-------------------------------|------------------------|--------------------|

### Option B: Block Format (one per system)

**System:** ___
- What does your team do with it? ___
- Tools you use to manage it: ___
- Where is the code/config/scripts? _(repo URL, server path, or "nowhere")_
- Where is documentation? _(Confluence link, shared drive, or "none")_
- Biggest pain point with this system: ___

### General Questions (always included)

- How do requests reach your team? _(Jira ticket / Slack / email / other)_
- What tasks repeat more than twice a week? ___
- What would you fix tomorrow if you had a free day? ___
- Who do you depend on most? _(team name + for what)_
- Who depends on you most? _(team name + for what)_

## Structured Output Format

After discovery + scanning, produce `$REPO/teams/<team>/discovery.md`:

```markdown
# Discovery: [Team Name]

**Last updated:** YYYY-MM-DD
**Discovery status:** [In Progress / Complete]
**Filled by:** [names]
**Reviewed by:** [names]

## Contacts

| Name | Email | Role |
|------|-------|------|

## Systems & Management Landscape

| System/Service | Responsibility | How managed | Tools | Automation assets | Code location | In git? | State |
|---------------|---------------|-------------|-------|-------------------|--------------|---------|-------|

### [System Name] — Detail

- **Found:** [what the agent discovered by scanning sources]
- **Gap:** [what's missing or unclear]
- **State:** Manual / Script / IaC
- **IaC readiness:** Low / Medium / High
- **Notes:** [additional context]

## Processes & Workflows

- Request intake: [how]
- Approval chain: [who]
- Avg time request → delivery: [estimate]
- Handoffs: [to/from whom]

## Dependencies

| We depend on (team/system) | They depend on us | For what |
|---------------------------|-------------------|----------|

## Pain Points

| Source | Pain point | Impact | Quick win? |
|--------|-----------|--------|------------|

## Self-Service Candidates

| Repeated request | Frequency | Automatable? | Complexity |
|-----------------|-----------|-------------|------------|

## Quick Win Candidates Identified (from meeting)

> Per project framework: 3-5 quick wins per team. List them with brief justification.

1. **<title>** — <one-line description>
2. ...

## Cross-Team Items (escalate to consolidated plan)

- **<item>** — joint with <other team> (link to their epic). Notes.

## Documentation Status

| Doc | Location | Current? | Notes |
|-----|----------|----------|-------|

## Discovery Summary

- **Total systems:** N
- **State breakdown:** X Manual, Y Script, Z IaC
- **Top IaC candidates:** [list]
- **Top quick wins:** [list]
- **Key risks:** [list]
```

## Source Scanning — How the Agent Investigates

When a team lists external sources (repos, Confluence pages, server paths), the agent scans them systematically.

### Git Repositories

For each repo URL provided:

1. **Clone or read via GitHub MCP:**
   - Use `mcp__plugin_github_github__get_file_contents` for specific files
   - Use `mcp__plugin_github_github__search_code` to find relevant files
   - Look in the org `final-il` by default

2. **What to look for:**
   - `README.md` — purpose, setup instructions, architecture
   - `*.tf`, `*.tfvars` — Terraform IaC (note modules, providers, state backend)
   - `*.yaml`, `*.yml` — Ansible playbooks, Kubernetes manifests, CI/CD pipelines
   - `Jenkinsfile`, `.github/workflows/`, `.gitlab-ci.yml` — CI/CD definitions
   - `scripts/`, `bin/` — Shell scripts, Python automation
   - `Dockerfile`, `docker-compose.yml` — Containerization
   - `Makefile` — Build/deploy automation
   - `.env.example`, `config/` — Configuration patterns
   - Commit frequency and recency (`git log --oneline -10`)

3. **Classify each finding:**
   - **State:** Manual (no code) / Script (bash/python) / IaC (Terraform/Ansible/K8s)
   - **Maturity:** Prototype / Working / Production / Maintained
   - **Coverage:** Does the code cover the full system or just parts?

### Confluence Pages

For each Confluence link provided:

1. **Read via MCP Atlassian:**
   - Use `mcp__mcp-atlassian__confluence_get_page` with the page ID or space+title
   - Use `mcp__mcp-atlassian__confluence_search` to find related pages

2. **What to look for:**
   - Architecture diagrams, network diagrams
   - Runbooks and operational procedures
   - System inventories and IP lists
   - Change management records
   - Onboarding/handover docs
   - Last updated date (is it stale?)

3. **Classify:**
   - **Current:** Updated within 6 months
   - **Stale:** 6-12 months without update
   - **Outdated:** 12+ months, likely inaccurate

### Server Paths / Shared Drives

The agent CANNOT directly access servers or shared drives. When a team says "scripts are on server X at /path/":

1. **Record the location** in discovery.md as-is
2. **Ask the team member** to paste the file listing or key scripts into the conversation
3. **Mark as "not scanned"** with reason: "requires direct server access"
4. **Suggest:** Move to git repo for version control and visibility

### What the Agent Records Per Source

For every source scanned, write to `$REPO/teams/<team>/sources/`:

```markdown
# Source: [name]

- **Type:** git-repo / confluence / server-path / shared-drive
- **Location:** [URL or path]
- **Scanned:** YYYY-MM-DD
- **Access:** OK / Requires auth / Inaccessible
- **Findings:**
  - [list of what was found: files, docs, scripts, configs]
- **State:** Manual / Script / IaC
- **Gaps:**
  - [what's missing, unclear, or outdated]
- **Recommendation:**
  - [e.g., "move to git", "update docs", "add CI/CD"]
```

### Scanning Strategy

1. **Breadth first:** Quickly scan all listed sources, record what exists
2. **Depth second:** For key systems, dive deep into code structure and docs
3. **Flag gaps immediately:** If a source is inaccessible or empty, record it and move on
4. **Cross-reference:** If multiple teams point to the same repo/page, note the overlap in `cross-team/dependencies.md`

## Interaction Modes

The agent accepts information through multiple channels:

1. **Confluence form** — team fills the form page, agent reads it via MCP Atlassian
2. **Direct conversation** — user pastes notes, shares links, describes systems verbally
3. **File upload** — user drops docs, scripts, configs into the conversation
4. **Source scanning** — agent reads repos and Confluence pages the team pointed to

In ALL cases, normalize the information into the structured output format above.

## Writing Rules

- All writes go to `$REPO/` using absolute paths
- Commit + push after every meaningful write (not batched)
- Only write to the current user's team folder (unless running cross-team analysis)
- Cross-team files are derived — regenerate from team data, never hand-edit
- Use absolute dates, never relative ("2026-05-05", not "today")
- When scanning external sources, note what was found AND what's missing

## Conflict Handling

- Pull before every write
- If conflict detected: show both versions, ask user which to keep
- Per-action commits minimize conflict window
- Team folders are implicitly owned by that team — conflicts should be rare

## Project Pillars Context

Discovery feeds into these initiatives (helps prioritize findings):
1. Transition to IaC
2. Process Standardization
3. Self-Service
4. Monitoring & Observability
5. CI/CD & Automation Pipelines
6. Security & Compliance
7. Knowledge Management
8. Automation
