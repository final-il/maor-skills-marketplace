---
name: technical-docs
description: "Generate structured technical documentation — architecture docs, runbooks, ADRs, API docs, postmortems, security reviews, and more. Use this skill whenever the user asks to write, create, or generate technical documentation, design documents, runbooks, playbooks, incident reports, postmortems, ADRs (architecture decision records), API documentation, onboarding guides, or any structured technical writing. Also trigger when the user says 'document this', 'write this up', 'create a doc for', or wants to turn architecture designs or code into documentation — even if they don't say 'documentation' explicitly."
---

# Technical Documentation Generator

You produce structured technical documents that are clear, complete, and ready to be consumed by humans or by other tools (docx, pptx, pdf skills). Every document you produce follows a consistent structure so downstream skills can reliably parse and transform it.

## Output Format

All documents are output as **structured markdown** with a consistent frontmatter header. This makes them both human-readable and machine-parseable for downstream skills (docx, pptx, pdf).

Every document starts with this frontmatter:

```yaml
---
doc_type: [architecture | runbook | adr | api | postmortem | security-review | onboarding | custom]
title: "Document Title"
author: ""
date: YYYY-MM-DD
version: "1.0"
status: [draft | review | approved | deprecated]
audience: [devops | security | engineering | leadership | all]
tags: [tag1, tag2, tag3]
---
```

This frontmatter enables downstream skills to apply the right template and formatting. For example, a `doc_type: architecture` with `audience: leadership` tells a pptx skill to use executive-friendly layouts.

## Document Types

Select the right template based on the user's request. If the request doesn't clearly match a type, ask. Read the relevant reference file for the full template.

| Type | When to Use | Reference |
|------|-------------|-----------|
| Architecture Document | System design, infrastructure, component overview | `references/architecture.md` |
| Runbook / Playbook | Operational procedures, step-by-step instructions | `references/runbook.md` |
| ADR (Architecture Decision Record) | Recording why a technical decision was made | `references/adr.md` |
| API Documentation | Endpoint docs, request/response formats, auth | `references/api-docs.md` |
| Postmortem / Incident Report | After an outage or incident | `references/postmortem.md` |
| Security Review | Threat model, security controls, risk assessment | `references/security-review.md` |

If the user's request doesn't fit any of these, use the general structure:

```markdown
# [Title]
## Overview
## Context
## Details
## Risks / Considerations
## Next Steps
```

## Writing Principles

1. **Audience-aware** — Adjust depth and jargon based on the audience. Leadership gets summaries and impact. Engineers get implementation detail. Security teams get controls and risks. When in doubt, layer it: executive summary up top, detail below.

2. **Scannable** — Use headers, tables, bullet points, and bold for key terms. A reader should be able to skim the document and understand the structure in 30 seconds.

3. **Complete but concise** — Include everything someone needs to act on the document. Leave out everything else. If a section doesn't add value for the stated audience, drop it.

4. **Actionable** — Every document should make it clear what happens next. Recommendations, action items, owners, and deadlines where applicable.

5. **Consistent structure** — Use the templates. Consistency across documents makes them easier to find, read, and maintain. It also enables downstream automation.

## Working with Other Skills

This skill is designed to produce output that other skills can consume:

- **docx skill** — Pass the markdown output to create a Word document. The frontmatter tells docx which template/style to apply.
- **pptx skill** — Pass the markdown output to create a presentation. `audience: leadership` signals to use executive layouts. Each `##` header becomes a slide.
- **pdf skill** — Pass the markdown output to create a PDF.
- **architecture-diagrams skill** — When a document needs diagrams, reference the architecture-diagrams skill to generate Mermaid/PlantUML/draw.io diagrams that can be embedded in the document.

When the user wants a final deliverable (Word, PowerPoint, PDF), produce the markdown first, then hand off to the appropriate skill.

## How to Handle Requests

1. **Identify the document type** from the user's request
2. **Read the reference template** for that type
3. **Ask clarifying questions** if critical information is missing (audience, scope, context)
4. **Generate the document** with frontmatter and full structure
5. **Offer next steps** — "Want me to create a Word doc from this? Add diagrams? Generate a presentation?"
