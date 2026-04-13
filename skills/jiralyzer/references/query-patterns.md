# Jiralyzer Query Patterns

Pre-built SQL patterns for common Jira analytics questions. All DuckDB SQL.

## Ticket Lifecycle

### Created vs Resolved over time
```sql
SELECT DATE_TRUNC('week', created) AS week,
       COUNT(*) AS created,
       COUNT(resolved) AS resolved
FROM tickets
GROUP BY 1 ORDER BY 1;
```

### Average resolution time by priority
```sql
SELECT priority,
       COUNT(*) AS ticket_count,
       ROUND(AVG(resolution_days), 1) AS avg_days,
       ROUND(MEDIAN(resolution_days), 1) AS median_days
FROM tickets
WHERE resolved IS NOT NULL
GROUP BY priority
ORDER BY avg_days DESC;
```

### Aging analysis (open tickets by age bucket)
```sql
SELECT CASE
         WHEN CURRENT_DATE - created::DATE <= 7 THEN '0-7 days'
         WHEN CURRENT_DATE - created::DATE <= 30 THEN '8-30 days'
         WHEN CURRENT_DATE - created::DATE <= 90 THEN '31-90 days'
         ELSE '90+ days'
       END AS age_bucket,
       COUNT(*) AS open_tickets
FROM tickets
WHERE resolved IS NULL
GROUP BY 1 ORDER BY 1;
```

### Resolution rate by project
```sql
SELECT project,
       COUNT(*) AS total,
       COUNT(resolved) AS resolved,
       ROUND(100.0 * COUNT(resolved) / COUNT(*), 1) AS resolve_pct
FROM tickets
GROUP BY project
ORDER BY total DESC;
```

## Status Transitions

### Status transition matrix
```sql
SELECT from_status, to_status, COUNT(*) AS transitions
FROM status_changes
GROUP BY 1, 2
ORDER BY transitions DESC;
```

### Cycle time by status (avg hours in each status)
```sql
WITH ordered AS (
    SELECT ticket_key, to_status AS status, changed_at,
           LEAD(changed_at) OVER (PARTITION BY ticket_key ORDER BY changed_at) AS next_change
    FROM status_changes
)
SELECT status,
       ROUND(AVG(EXTRACT(EPOCH FROM (next_change - changed_at)) / 3600.0), 1) AS avg_hours,
       COUNT(*) AS transitions
FROM ordered
WHERE next_change IS NOT NULL
GROUP BY status
ORDER BY avg_hours DESC;
```

### Tickets that bounced back
```sql
SELECT sc.ticket_key, t.summary, sc.from_status, sc.to_status, sc.changed_at
FROM status_changes sc
JOIN tickets t ON t.id = sc.ticket_id
WHERE sc.to_status IN ('Open', 'Reopened', 'To Do')
  AND sc.from_status NOT IN ('Open', 'Reopened', 'To Do')
ORDER BY sc.changed_at DESC
LIMIT 20;
```

## Re-Assignments

### Most re-assigned tickets
```sql
SELECT t.key, t.summary, COUNT(a.id) AS reassignments
FROM tickets t
JOIN assignments a ON t.id = a.ticket_id
GROUP BY t.key, t.summary
HAVING COUNT(a.id) > 1
ORDER BY reassignments DESC
LIMIT 20;
```

### Who receives the most tickets
```sql
SELECT to_assignee, COUNT(*) AS received_count
FROM assignments
WHERE to_assignee IS NOT NULL
GROUP BY to_assignee
ORDER BY received_count DESC;
```

### Transfer patterns (from -> to pairs)
```sql
SELECT from_assignee, to_assignee, COUNT(*) AS transfers
FROM assignments
WHERE from_assignee IS NOT NULL AND to_assignee IS NOT NULL
GROUP BY 1, 2
ORDER BY transfers DESC
LIMIT 20;
```

## Workload

### Tickets per assignee by status
```sql
SELECT assignee,
       COUNT(*) FILTER (WHERE resolved IS NULL) AS open_tickets,
       COUNT(*) FILTER (WHERE resolved IS NOT NULL) AS closed_tickets,
       COUNT(*) AS total
FROM tickets
WHERE assignee IS NOT NULL
GROUP BY assignee
ORDER BY open_tickets DESC;
```

### Workload trend (tickets assigned per week)
```sql
SELECT DATE_TRUNC('week', a.changed_at) AS week,
       a.to_assignee AS assignee,
       COUNT(*) AS tickets_received
FROM assignments a
WHERE a.to_assignee IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

## Comments & Activity

### Most commented tickets
```sql
SELECT t.key, t.summary, COUNT(c.id) AS comment_count
FROM tickets t
JOIN comments c ON t.id = c.ticket_id
GROUP BY t.key, t.summary
ORDER BY comment_count DESC
LIMIT 20;
```

### Comment activity over time
```sql
SELECT DATE_TRUNC('week', created_at) AS week,
       COUNT(*) AS comments
FROM comments
GROUP BY 1 ORDER BY 1;
```

## Time Tracking

### Tickets with most time spent
```sql
SELECT t.key, t.summary,
       ROUND(SUM(w.time_spent_secs) / 3600.0, 1) AS hours_logged
FROM tickets t
JOIN worklogs w ON t.id = w.ticket_id
GROUP BY t.key, t.summary
ORDER BY hours_logged DESC
LIMIT 20;
```

### Time estimated vs actual
```sql
SELECT t.key, t.summary,
       ROUND(t.time_original_estimate_secs / 3600.0, 1) AS estimated_hours,
       ROUND(t.time_spent_secs / 3600.0, 1) AS actual_hours,
       ROUND((t.time_spent_secs - t.time_original_estimate_secs) / 3600.0, 1) AS variance_hours
FROM tickets t
WHERE t.time_original_estimate_secs > 0
ORDER BY variance_hours DESC;
```

## Patterns

### Day-of-week creation patterns
```sql
SELECT DAYNAME(created) AS day_of_week,
       DAYOFWEEK(created) AS day_num,
       COUNT(*) AS tickets_created
FROM tickets
GROUP BY 1, 2
ORDER BY day_num;
```

### Ticket type distribution
```sql
SELECT issue_type, COUNT(*) AS count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM tickets
GROUP BY issue_type
ORDER BY count DESC;
```

### Labels usage
```sql
SELECT label, COUNT(*) AS ticket_count
FROM tickets, unnest(labels) AS label
GROUP BY label
ORDER BY ticket_count DESC
LIMIT 20;
```
