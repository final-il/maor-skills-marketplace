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
cd /Users/maorb/git/jiralyzer && uv run jiralyzer <command> [args...]
```

Every `jiralyzer` command shown in this skill should be run this way. For example:
- `jiralyzer stats` → `cd /Users/maorb/git/jiralyzer && uv run jiralyzer stats`
- `jiralyzer query "SELECT ..."` → `cd /Users/maorb/git/jiralyzer && uv run jiralyzer query "SELECT ..."`

The default database path is `jiralyzer.db` in the current directory (`/Users/maorb/git/jiralyzer/jiralyzer.db`). Use `--db <path>` to override.

## Prerequisites

A database must be populated before analysis:

```bash
# Ingest data (from Jira REST API JSON export with expand=changelog)
cd /Users/maorb/git/jiralyzer && uv run jiralyzer ingest export.json

# Verify
cd /Users/maorb/git/jiralyzer && uv run jiralyzer stats
```

If the user hasn't ingested data yet, guide them to:
1. Export from Jira REST API with `expand=changelog` (provides full history)
2. Run `cd /Users/maorb/git/jiralyzer && uv run jiralyzer ingest <path-to-json>`

## Workflow

When the user asks an analytics question:

### 1. Check database exists

Run `cd /Users/maorb/git/jiralyzer && uv run jiralyzer schema` to verify data is loaded. If it fails or returns empty, guide the user to ingest data first.

### 2. Understand the schema

Run `cd /Users/maorb/git/jiralyzer && uv run jiralyzer schema` to get the current table structure. The database has 6 tables:

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
cd /Users/maorb/git/jiralyzer && uv run jiralyzer query "<sql>" --format json

# For display to user
cd /Users/maorb/git/jiralyzer && uv run jiralyzer query "<sql>" --format table
```

Always explain what the results mean in context. Don't just show numbers — provide insights.

### 5. Visualize when appropriate

If the results benefit from a chart, generate one:

```bash
cd /Users/maorb/git/jiralyzer && uv run jiralyzer chart "<sql>" --type <chart_type> --x <col> --y <col> --output chart.html --open
```

See `references/visualization-guide.md` for chart type selection guidance.

Chart types: `bar`, `line`, `pie`, `histogram`, `scatter`, `heatmap`, `stacked_bar`
Output formats: `.html` (interactive Plotly), `.png` (static Matplotlib)

### 6. Present narrative

Combine data and visualization into a concise report:
- Lead with the key insight
- Show the numbers that support it
- Link to the chart if generated
- Suggest follow-up questions

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
cd /Users/maorb/git/jiralyzer && uv run jiralyzer stats              # Text summary
cd /Users/maorb/git/jiralyzer && uv run jiralyzer stats --format json  # Machine-readable
```

This shows: table row counts, date ranges, status distribution, top assignees, resolution metrics.

## Export

For downstream analysis (Snowflake, BigQuery, etc.):

```bash
cd /Users/maorb/git/jiralyzer && uv run jiralyzer export-parquet ./exports/                    # All tables
cd /Users/maorb/git/jiralyzer && uv run jiralyzer export-parquet ./exports/ --tables tickets    # Specific tables
cd /Users/maorb/git/jiralyzer && uv run jiralyzer export-parquet ./exports/ --compression zstd  # Better compression
```

## Rules

- Always run commands via `cd /Users/maorb/git/jiralyzer && uv run jiralyzer <command>` — never use bare `jiralyzer`
- Never access the database directly — always use the CLI
- Default DB path is `jiralyzer.db` in the jiralyzer project directory; use `--db <path>` to override
- When generating SQL, prefer CTEs over subqueries for readability
- Always LIMIT results for exploratory queries (LIMIT 20 default)
- If a query fails, check the schema and adjust — column names are exact
