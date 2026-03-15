# Architecture Document Template

```yaml
---
doc_type: architecture
title: "[System/Component Name] Architecture"
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
# [System Name] Architecture

## Executive Summary
2-3 sentences: what this system does, why it exists, and its key quality attributes
(availability, security, performance).

## Context
- Business problem being solved
- Key stakeholders and their concerns
- Constraints (budget, timeline, compliance, existing infrastructure)

## Architecture Overview
High-level description of the system. Reference an architecture diagram here
(use the architecture-diagrams skill to generate one).

## Components
For each major component:

### [Component Name]
- **Purpose**: What it does and why
- **Technology**: What it's built with
- **Interfaces**: How other components interact with it
- **Data**: What data it owns/processes
- **Scaling**: How it scales (horizontal, vertical, auto)

## Data Flow
Step-by-step flow of data through the system for the primary use case(s).
Use numbered steps. Reference security controls at each boundary.

## Infrastructure
- Cloud provider and services
- Networking (VPCs, subnets, connectivity)
- Compute (containers, serverless, VMs)
- Storage (databases, object storage, caching)
- Environments (dev, staging, prod)

## Security
- Authentication and authorization
- Encryption (at rest, in transit)
- Network security controls
- Secrets management
- Compliance requirements

## Reliability
- Availability target (SLA/SLO)
- Failure modes and recovery
- Backup and disaster recovery
- Monitoring and alerting

## Trade-offs and Alternatives
What alternatives were considered and why this approach was chosen.
Link to ADRs for specific decisions.

## Risks and Open Questions
| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| ... | ... | ... | ... |

## Appendix
- Glossary of terms
- Links to related documents
- Diagram source files
```
