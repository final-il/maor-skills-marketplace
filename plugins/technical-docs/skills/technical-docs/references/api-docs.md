# API Documentation Template

```yaml
---
doc_type: api
title: "[API Name] Documentation"
author: ""
date: YYYY-MM-DD
version: "1.0"
status: draft
audience: engineering
tags: []
---
```

## Structure

```markdown
# [API Name] API Documentation

## Overview
What this API does, who it's for, and the base URL.

## Authentication
How to authenticate (API key, OAuth, JWT, etc.).
Include example headers.

## Base URL
| Environment | URL |
|-------------|-----|
| Production | `https://api.example.com/v1` |
| Staging | `https://api-staging.example.com/v1` |

## Rate Limits
| Tier | Requests/min | Burst |
|------|-------------|-------|
| ... | ... | ... |

## Endpoints

### [Resource Name]

#### [METHOD] /path

**Description**: What this endpoint does.

**Authorization**: Required role/scope.

**Request**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| ... | ... | ... | ... |

**Request body** (if applicable):
\```json
{
  "field": "value"
}
\```

**Response** (200 OK):
\```json
{
  "id": "abc-123",
  "field": "value"
}
\```

**Error responses**:
| Status | Code | Description |
|--------|------|-------------|
| 400 | INVALID_REQUEST | Description |
| 401 | UNAUTHORIZED | Description |
| 404 | NOT_FOUND | Description |

---

## Error Handling
Common error format and how to handle errors.

## Pagination
How pagination works (cursor, offset, etc.).

## Versioning
API versioning strategy and deprecation policy.

## SDKs and Examples
Links to client libraries and code examples.

## Changelog
| Date | Version | Changes |
|------|---------|---------|
| ... | ... | ... |
```
