# Security Review Template

```yaml
---
doc_type: security-review
title: "Security Review: [System/Feature Name]"
author: ""
date: YYYY-MM-DD
version: "1.0"
status: draft
audience: security
tags: []
---
```

## Structure

```markdown
# Security Review: [System/Feature Name]

## Executive Summary
2-3 sentences: what was reviewed, overall risk posture, key findings.

## Scope
- What systems/components are in scope
- What is explicitly out of scope
- Review methodology (threat modeling, code review, config audit, pen test)

## System Overview
Brief description of the system architecture. Reference architecture docs
and diagrams.

## Threat Model
Identify threat actors and attack vectors relevant to this system.

### Threat Actors
| Actor | Motivation | Capability |
|-------|-----------|------------|
| External attacker | Data theft, disruption | Medium |
| Insider threat | Data exfiltration | High (privileged access) |
| Supply chain | Compromise via dependency | Low-Medium |

### Attack Surface
| Surface | Exposure | Controls |
|---------|----------|----------|
| Public API | Internet-facing | WAF, auth, rate limiting |
| Admin interface | Internal network | VPN, MFA, RBAC |
| Database | Private subnet | SG, encryption, IAM |

## Findings

### Finding 1: [Title]
- **Severity**: Critical / High / Medium / Low / Informational
- **Description**: What the issue is
- **Impact**: What could happen if exploited
- **Recommendation**: How to fix it
- **Status**: Open / In Progress / Resolved

### Finding 2: [Title]
...

## Security Controls Assessment
| Control | Status | Notes |
|---------|--------|-------|
| Authentication | Implemented | OAuth 2.0 + MFA |
| Authorization | Partial | RBAC exists but no attribute-based controls |
| Encryption at rest | Implemented | AES-256 via KMS |
| Encryption in transit | Implemented | TLS 1.2+ enforced |
| Logging & monitoring | Partial | CloudTrail enabled, no alerting |
| Secrets management | Implemented | Secrets Manager with rotation |
| Network segmentation | Implemented | Private subnets, NACLs, SGs |

## Risk Summary
| Risk | Severity | Likelihood | Recommendation |
|------|----------|-----------|----------------|
| ... | ... | ... | ... |

## Recommendations
Prioritized list: must-do, should-do, nice-to-have.

## Sign-off
| Role | Name | Date | Decision |
|------|------|------|----------|
| Security Lead | | | Approved / Conditional / Rejected |
| Engineering Lead | | | Acknowledged |
```
