---
name: jiralyzer
description: |
  Jira ticket analytics using natural language. Trigger when user asks about Jira ticket data,
  resolution times, re-assignment patterns, workload distribution, status transitions, ticket
  analytics, cycle time, or burndown metrics.

  Also trigger for: "analyze my Jira tickets", "show me ticket trends", "Jira dashboard",
  "ticket metrics", "cycle time analysis", "who has the most tickets", "resolution time by priority",
  "most re-assigned tickets", "status transition matrix", "workload distribution".
---

# Jiralyzer — Natural Language Jira Analytics

You help users analyze Jira ticket data using the `jiralyzer` CLI tool. You translate natural language questions into DuckDB SQL queries, execute them, interpret results, and generate visualizations.

## First-Time Setup

Before doing anything else, verify the environment is ready by running the setup script. **Tell the user to run it interactively** — it prompts for credentials and configures everything:

```
! /Users/maorb/git-dev/jiralyzer/setup.sh
```

Tell the user to type `! /Users/maorb/git-dev/jiralyzer/setup.sh` in the Claude Code prompt — the `!` prefix runs it interactively so the user can provide input.

The script handles:
1. Installs `uv` if missing
2. Prompts for Jira credentials and paths, creates `.env`
3. Runs `uv sync` with SSL cert for corporate proxy
4. Verifies `jiralyzer` CLI works
5. Creates chart output directory
6. Tests Jira API connectivity

**All checks must pass (green).** If any fail (red), the script tells the user what to fix and they re-run it. **Do not proceed with any analysis until setup reports all green.**

## How to Run Commands

**All commands use the `run.sh` wrapper.** It sources `.env`, sets the working directory, and passes arguments to `jiralyzer`:

```bash
/Users/maorb/git-dev/jiralyzer/run.sh <command> [args...]
```

Examples:
```bash
/Users/maorb/git-dev/jiralyzer/run.sh stats
/Users/maorb/git-dev/jiralyzer/run.sh query "SELECT * FROM tickets LIMIT 5"
/Users/maorb/git-dev/jiralyzer/run.sh sync --project CREQ
```

For brevity, the rest of this document shows commands as:
```bash
run.sh <command> [args...]
```

But **every invocation** must use the full path `/Users/maorb/git-dev/jiralyzer/run.sh`.

## Workflow

When the user asks an analytics question:

### 1. Identify the target project and ensure its data is loaded

**This step is critical.** The database can contain multiple projects. You must determine which project the user is asking about and verify that project's data is present.

1. **Extract the project key** from the user's request (e.g., "analyze CSI-PM" → project key is `CSI-PM`, "CREQ tickets" → project key is `CREQ`).

2. **Check which projects are in the database:**
   ```bash
   run.sh query "SELECT project, COUNT(*) as count FROM tickets GROUP BY project ORDER BY count DESC"
   ```

3. **If the requested project is NOT in the results, sync it first:**
   ```bash
   run.sh sync --project <KEY>
   ```
   If sync fails, stop and report the error to the user. Do not attempt alternative data loading methods.

4. **If the database has no data at all**, ask the user for their Jira project key and run sync.

5. **Always filter queries by project** when multiple projects exist in the database. Add `WHERE project = '<KEY>'` to all queries. Do NOT mix data from different projects.

### 2. Understand the schema

Run `run.sh schema` to get the current table structure. The database has 6 tables:

- **tickets** — One row per Jira issue (key, status, assignee, priority, resolution_days, etc.)
- **status_changes** — Status transition history from changelog
- **assignments** — Assignee change history from changelog
- **comments** — Issue comments
- **custom_fields** — Flexible key-value store for custom fields
- **worklogs** — Time tracking entries

See `references/schema.md` for detailed column descriptions and types.

### 3. Generate SQL

Translate the user's question into DuckDB SQL. Key considerations:

- DuckDB SQL is PostgreSQL-compatible with extensions (FILTER, MEDIAN, list functions)
- Array columns (labels, components, fix_versions, affects_versions) use `unnest()` for expansion
- `resolution_days` is a generated column — no need to compute it
- Use `references/query-patterns.md` for pre-built patterns matching common questions

### 4. Execute and interpret

```bash
# For data analysis
run.sh query "<sql>" --format json

# For display to user
run.sh query "<sql>" --format table
```

Always explain what the results mean in context. Don't just show numbers — provide insights.

### 5. Visualize when appropriate

If the results benefit from a chart, generate one:

```bash
run.sh chart "<sql>" --type <chart_type> --x <col> --y <col> --output /Users/maorb/git-dev/jiralyzer/charts/<name>.png
```

See `references/visualization-guide.md` for chart type selection guidance.

Chart types: `bar`, `line`, `pie`, `histogram`, `scatter`, `heatmap`, `stacked_bar`
Output formats: `.png` (static Matplotlib, **default — works reliably**), `.html` (interactive Plotly — may be blank behind corporate proxies)

### 6. Present narrative

Combine data and visualization into a concise report:
- Lead with the key insight
- Show the numbers that support it
- Link to the chart if generated
- Suggest follow-up questions

## Semantic Analysis (Categorize, Classify, Understand)

When the user asks to **categorize**, **classify**, **segment**, or **understand** their ticket data, do NOT fall back to SQL `LIKE` keyword matching. You are an LLM — use your semantic understanding.

### Approach

1. **Sample first, don't dump everything.** Query a representative batch (50-100 tickets) with summaries:
   ```bash
   run.sh query "SELECT key, summary, issue_type, priority, status, assignee FROM tickets WHERE project = '<KEY>' ORDER BY key LIMIT 100" --format json
   ```

2. **Read and understand the summaries yourself.** Look for themes, patterns, team names, work types, naming conventions, repeated structures. You are the classifier — not SQL.

3. **Build categories from what you see.** After reading the sample, define categories (e.g., by domain, by work type, by repetitiveness). Then query more batches if needed to validate.

4. **Use SQL only for aggregation, not classification.** Once you've identified categories and the patterns that define them, you can use SQL `CASE WHEN` for counting. But the category definitions come from your semantic understanding, not from guessing keywords.

5. **Read ALL tickets, but in chunks.** It is critical to read every ticket for thorough analysis. Use batches of 50-100 with `OFFSET` and `LIMIT`. After each batch, note the patterns and categories you've found so far, then continue to the next batch. This prevents context overflow while ensuring complete coverage.

6. **Identify automation candidates** by looking for:
   - Near-identical summaries (repetitive tasks)
   - Formulaic naming patterns (e.g., "Q2 - {project}: {task} - {team}")
   - Recurring work types that follow a template

7. **Present findings incrementally.** Write your analysis text as you go — don't accumulate everything and try to output it all at once. After each major finding, share it with the user.

### What NOT to do
- Don't dump all tickets in a single query — read in chunks of 50-100 to manage context
- Don't use `LIKE '%keyword%'` as your primary classification strategy
- Don't skip reading the actual ticket content — SQL aggregation on unread data produces shallow insights

## Generating Charts

**Always prefer the `jiralyzer chart` CLI** for visualizations. It produces professional styled PNG charts automatically.

```bash
run.sh chart "<sql>" --type bar --x <col> --y <col> --output /Users/maorb/git-dev/jiralyzer/charts/<name>.png
```

If you need a custom visualization that the CLI can't produce:
1. **Write the Python script to a file first**, then run it. Do NOT write large inline Python in Bash calls — it times out.
   ```bash
   cat > /tmp/chart_script.py << 'PYEOF'
   import matplotlib.pyplot as plt
   # ... your code ...
   PYEOF
   /Users/maorb/git-dev/jiralyzer/.venv/bin/python3 /tmp/chart_script.py
   ```
2. Keep scripts short — one chart per script, not six.
3. Use the jiralyzer `.venv` Python so matplotlib is available.

## Common Question Patterns

| User asks about... | Tables to query | Typical chart |
|---|---|---|
| Resolution time | tickets (resolution_days) | histogram, bar |
| Status distribution | tickets (status) | pie, bar |
| Workload / assignees | tickets (assignee) | bar |
| Ticket trends | tickets (created, resolved) | line |
| Re-assignments | assignments | bar |
| Status transitions | status_changes | heatmap, stacked_bar |
| Cycle time | status_changes (time between states) | histogram, line |
| Activity / comments | comments | line, bar |
| Time tracking | worklogs | bar, scatter |
| Custom fields | custom_fields | bar |

## Quick Stats

For a quick overview, run:

```bash
run.sh stats              # Text summary
run.sh stats --format json  # Machine-readable
```

This shows: table row counts, date ranges, status distribution, top assignees, resolution metrics.

## Dashboard

For an interactive web view of the analytics, run:

```bash
./run.sh dashboard
```

This launches a Streamlit app at `http://localhost:8501` with five tabs (Overview, Aging, Workload, Story Points, Categories), sidebar filters (project, team, assignee, date range), and live auto-refresh on `jiralyzer.db` changes.

Useful flags:

```bash
./run.sh dashboard --port 8888    # custom port
./run.sh dashboard --no-browser   # don't auto-open the browser
```

The dashboard reads the database **read-only** — concurrent `./run.sh sync` calls are safe. While the dashboard is open, you can run `./run.sh sync --project <KEY>` in another terminal and the charts refresh within ~5 seconds.

## Pinning Analyses

After producing a useful analysis (SQL + chart), offer to pin it so it shows up in the
dashboard's "My Analyses" tab. Pinned analyses re-run free at view time — no LLM call,
no Zscaler dance, and they compose with the dashboard's sidebar filters.

### When to offer a pin

Offer to pin **after** the user has seen the result and explicitly liked it. Phrase it
as a yes/no: *"Pin this as `velocity-by-team`? (y/n)"*. Do NOT pin silently or in bulk.
Never auto-pin — if the user declines, do nothing.

### How to pin

1. Build a JSON spec for the analysis. Use `{WHERE}` or `{AND}` tokens in the SQL so
   the dashboard's sidebar filters narrow the pin just like the built-in tabs.
2. Write the spec to a tmp path (e.g. `/tmp/<id>.json`).
3. Call `./run.sh pin save --from-json <tmp_path>`.
4. Confirm to the user that the pin is saved and visible in the dashboard's
   "My Analyses" tab.

### JSON template

```json
{
  "id": "velocity-by-team",
  "title": "Velocity by team (last 90d)",
  "description": "Resolved tickets per team over the trailing 90 days.",
  "sql": "SELECT team, COUNT(*) AS n FROM tickets WHERE resolved IS NOT NULL {AND} GROUP BY team",
  "chart": {"type": "bar", "x": "team", "y": "n", "color_by": null},
  "created_at": "2026-05-25",
  "tags": ["velocity"]
}
```

### Rules

- **Pin id**: must match `[a-z0-9-]+` (lowercase letters, digits, hyphens). The
  dashboard URL/file uses this id. Slug the title to derive a sensible default
  (e.g. "Velocity by team" → `velocity-by-team`).
- **Title**: free-form, shown as the chart heading.
- **SQL**: embed `{WHERE}` (clean SELECT with no existing WHERE) or `{AND}` (SQL
  already has its own WHERE) so sidebar filters compose. A pin without a token
  will run unfiltered — discouraged. Rewrite the SQL to add the right token
  before pinning if the original analysis didn't include one.
- **Chart types**: `bar`, `line`, `pie`, `scatter`, `histogram`. For `pie` use
  `names`/`values` keys instead of `x`/`y`. For `histogram`, only `x` is
  required.
- **created_at**: ISO date `YYYY-MM-DD`. The CLI will auto-stamp today's date if
  you omit the field.
- **Pin storage location**: `~/.jiralyzer/analyses/<id>.json`. Override with the
  `JIRALYZER_PINS_DIR` env var.
- **Overwrite**: re-pinning the same id requires `--overwrite`. Default refuses
  with a clear error — re-prompt the user (overwrite or rename?) and act on
  their answer.

### Example flow (skill transcript)

> User: *"Show me velocity by team"*
>
> Skill: *(runs analysis, shows chart)* *"That looks like a useful regular metric.
> Pin this as `velocity-by-team` so it shows in the dashboard? (y/n)"*
>
> User: *"y"*
>
> Skill: *(writes `/tmp/velocity-by-team.json`, runs `./run.sh pin save --from-json /tmp/velocity-by-team.json`)*
> *"Pinned. Open the dashboard's 'My Analyses' tab to see it."*

### Listing & managing pins

```bash
./run.sh pin list             # show id, title, created_at, tags
./run.sh pin show <id>        # print the JSON spec
./run.sh pin delete <id>      # remove the pin (prompts for confirmation)
```

## Export

For downstream analysis (Snowflake, BigQuery, etc.):

```bash
run.sh export-parquet ./exports/                    # All tables
run.sh export-parquet ./exports/ --tables tickets    # Specific tables
run.sh export-parquet ./exports/ --compression zstd  # Better compression
```

## Rules

- **Always use `run.sh` to invoke commands.** Full path: `/Users/maorb/git-dev/jiralyzer/run.sh <command>`. Never call `jiralyzer` directly or source `.env` manually.
- Never access the database directly — always use the CLI via `run.sh`
- **If `run.sh` fails with ".env not found", tell the user to run `setup.sh` first.** Do not attempt workarounds.
- **Always identify the target project first.** Check which projects are loaded, sync if needed, and filter all queries with `WHERE project = '<KEY>'` when multiple projects exist
- When generating SQL, prefer CTEs over subqueries for readability
- Always LIMIT results for exploratory queries (LIMIT 20 default)
- If a query fails, check the schema and adjust — column names are exact
