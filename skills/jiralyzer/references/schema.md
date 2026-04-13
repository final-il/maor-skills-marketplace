# Jiralyzer Schema Reference

6 DuckDB tables. Source: Jira REST API JSON with `expand=changelog`.

## tickets

One row per Jira issue. Central fact table.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Jira internal issue ID |
| key | VARCHAR NOT NULL | Issue key, e.g. `PROJ-123` |
| project | VARCHAR | Project key extracted from issue key |
| summary | VARCHAR | Issue title/summary |
| description | VARCHAR | Full description (ADF flattened to text) |
| issue_type | VARCHAR | Bug, Story, Task, Epic, Sub-task, etc. |
| priority | VARCHAR | Highest, High, Medium, Low, Lowest |
| status | VARCHAR | Current status (Open, In Progress, Done, etc.) |
| resolution | VARCHAR | Fixed, Won't Fix, Duplicate, etc. (NULL if open) |
| assignee | VARCHAR | Current assignee display name |
| reporter | VARCHAR | Reporter display name |
| created | TIMESTAMP | When the ticket was created |
| updated | TIMESTAMP | Last update timestamp |
| resolved | TIMESTAMP | When resolved (NULL if open) |
| due_date | DATE | Due date if set |
| environment | VARCHAR | Environment field |
| labels | VARCHAR[] | Array of labels — use `unnest(labels)` to expand |
| components | VARCHAR[] | Array of component names |
| fix_versions | VARCHAR[] | Array of fix version names |
| affects_versions | VARCHAR[] | Array of affected version names |
| parent_id | INTEGER | Parent issue ID (for sub-tasks) |
| epic_link | VARCHAR | Epic key if linked to an epic |
| story_points | DOUBLE | Story point estimate |
| time_original_estimate_secs | INTEGER | Original time estimate in seconds |
| time_spent_secs | INTEGER | Total time spent in seconds |
| resolution_days | DOUBLE (GENERATED) | Days from created to resolved — auto-computed |

**Key notes:**
- `resolution_days` is a virtual column: `EPOCH(resolved - created) / 86400.0`
- Array columns need `unnest()`: `SELECT t.key, label FROM tickets t, unnest(t.labels) AS label`
- `resolution IS NULL` means the ticket is still open

## status_changes

One row per status transition from changelog.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| ticket_id | INTEGER | References tickets.id |
| ticket_key | VARCHAR | Issue key |
| author | VARCHAR | Who made the change |
| changed_at | TIMESTAMP | When the status changed |
| from_status | VARCHAR | Previous status |
| to_status | VARCHAR | New status |

## assignments

One row per assignee change from changelog.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| ticket_id | INTEGER | References tickets.id |
| ticket_key | VARCHAR | Issue key |
| author | VARCHAR | Who made the change |
| changed_at | TIMESTAMP | When changed |
| from_assignee | VARCHAR | Previous assignee |
| to_assignee | VARCHAR | New assignee |

## comments

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Jira comment ID |
| ticket_id | INTEGER | References tickets.id |
| ticket_key | VARCHAR | Issue key |
| author | VARCHAR | Comment author |
| created_at | TIMESTAMP | When created |
| updated_at | TIMESTAMP | Last edit |
| body | VARCHAR | Comment text (ADF flattened) |

## custom_fields

Flexible key-value store. PK: (ticket_id, field_name).

| Column | Type | Description |
|--------|------|-------------|
| ticket_id | INTEGER | References tickets.id |
| ticket_key | VARCHAR | Issue key |
| field_name | VARCHAR | Custom field ID (e.g. `customfield_10789`) |
| field_value | VARCHAR | Value as string |

## worklogs

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Worklog ID |
| ticket_id | INTEGER | References tickets.id |
| ticket_key | VARCHAR | Issue key |
| author | VARCHAR | Who logged work |
| started_at | TIMESTAMP | When work started |
| time_spent_secs | INTEGER | Duration in seconds |
| comment | VARCHAR | Worklog description |

## DuckDB-Specific Syntax

```sql
-- Array expansion
SELECT t.key, label FROM tickets t, unnest(t.labels) AS label;

-- FILTER clause (conditional aggregation)
COUNT(*) FILTER (WHERE resolved IS NOT NULL) AS resolved_count

-- MEDIAN aggregate
MEDIAN(resolution_days)

-- Date functions
DATE_TRUNC('week', created)
DAYNAME(created)  -- 'Monday', 'Tuesday', etc.
EXTRACT(EPOCH FROM (ts2 - ts1))  -- seconds between timestamps
```
