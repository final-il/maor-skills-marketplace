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

## How to Run Commands

Jiralyzer is a Python package managed with `uv`. **All commands must be run from the jiralyzer project directory using `uv run`:**

```bash
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer <command> [args...]
```

Every `jiralyzer` command shown in this skill should be run this way. For example:
- `jiralyzer stats` → `cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer stats`
- `jiralyzer query "SELECT ..."` → `cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer query "SELECT ..."`

The default database path is `jiralyzer.db` in the current directory (`/Users/maorb/git-dev/jiralyzer/jiralyzer.db`). Use `--db <path>` to override.

## Data Loading

Before querying, ensure data is in the database. The `sync` command pulls directly from Jira REST API:

```bash
# Set Jira credentials (one-time setup)
export JIRA_URL=https://your-site.atlassian.net
export JIRA_EMAIL=your-email@example.com
export JIRA_API_TOKEN=your-api-token

# Full sync — all issues in a project
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer sync --project <KEY>

# Incremental sync — only issues updated since a date
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer sync --project <KEY> --since 2026-04-01

# Optionally save raw JSON export
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer sync --project <KEY> --output export.json
```

The sync command fetches all issues with `expand=changelog` (full history including status changes, assignments, worklogs) and automatically ingests them into DuckDB.

## Workflow

When the user asks an analytics question:

### 1. Identify the target project and ensure its data is loaded

**This step is critical.** The database can contain multiple projects. You must determine which project the user is asking about and verify that project's data is present.

1. **Extract the project key** from the user's request (e.g., "analyze CSI-PM" → project key is `CSI-PM`, "CREQ tickets" → project key is `CREQ`).

2. **Check which projects are in the database:**
   ```bash
   cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer query "SELECT project, COUNT(*) as count FROM tickets GROUP BY project ORDER BY count DESC"
   ```

3. **If the requested project is NOT in the results, sync it first:**
   ```bash
   cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer sync --project <KEY>
   ```
   This requires JIRA_URL, JIRA_EMAIL, and JIRA_API_TOKEN environment variables. If they're not set, ask the user to set them.

4. **If the database has no data at all**, ask the user for their Jira project key and run sync.

5. **Always filter queries by project** when multiple projects exist in the database. Add `WHERE project = '<KEY>'` to all queries. Do NOT mix data from different projects.

### 2. Understand the schema

Run `cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer schema` to get the current table structure. The database has 6 tables:

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
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer query "<sql>" --format json

# For display to user
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer query "<sql>" --format table
```

Always explain what the results mean in context. Don't just show numbers — provide insights.

### 5. Visualize when appropriate

If the results benefit from a chart, generate one:

```bash
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer chart "<sql>" --type <chart_type> --x <col> --y <col> --output chart.png
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
   cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer query "SELECT key, summary, issue_type, priority, status, assignee FROM tickets WHERE project = '<KEY>' ORDER BY key LIMIT 100" --format json
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
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer chart "<sql>" --type bar --x <col> --y <col> --output chart.png
```

If you need a custom visualization that the CLI can't produce:
1. **Write the Python script to a file first**, then run it. Do NOT write large inline Python in Bash calls — it times out.
   ```bash
   cat > /tmp/chart_script.py << 'PYEOF'
   import matplotlib.pyplot as plt
   # ... your code ...
   PYEOF
   cd /Users/maorb/git-dev/jiralyzer && .venv/bin/python3 /tmp/chart_script.py
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
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer stats              # Text summary
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer stats --format json  # Machine-readable
```

This shows: table row counts, date ranges, status distribution, top assignees, resolution metrics.

## Export

For downstream analysis (Snowflake, BigQuery, etc.):

```bash
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer export-parquet ./exports/                    # All tables
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer export-parquet ./exports/ --tables tickets    # Specific tables
cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer export-parquet ./exports/ --compression zstd  # Better compression
```

## Rules

- Always run commands via `cd /Users/maorb/git-dev/jiralyzer && uv run jiralyzer <command>` — never use bare `jiralyzer`
- Never access the database directly — always use the CLI
- Default DB path is `jiralyzer.db` in the jiralyzer project directory; use `--db <path>` to override
- **Always identify the target project first.** Check which projects are loaded, sync if needed, and filter all queries with `WHERE project = '<KEY>'` when multiple projects exist
- When generating SQL, prefer CTEs over subqueries for readability
- Always LIMIT results for exploratory queries (LIMIT 20 default)
- If a query fails, check the schema and adjust — column names are exact
