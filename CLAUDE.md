# Maor's Skills Marketplace — Project Instructions

## Overview

A Claude Code skills marketplace hosted at `final-il/maor-skills-marketplace`. Users install it via `/plugin` → Marketplace → Add Marketplace → `final-il/maor-skills-marketplace`.

## Repository Structure

```
maor-skills-marketplace/
├── CLAUDE.md                          ← You are here
├── README.md
├── .claude-plugin/
│   └── marketplace.json               ← Marketplace config — lists all plugins/skills
└── skills/
    ├── aws-secure-architecture/
    │   ├── SKILL.md                    ← Main skill file
    │   └── references/
    │       ├── private-to-saas.md      ← Private account → SaaS via API GW proxy pattern
    │       ├── multi-account-network.md ← Centralized egress/inspection pattern
    │       └── zero-trust-service-mesh.md ← Service-to-service auth pattern
    ├── technical-docs/
    │   ├── SKILL.md
    │   └── references/
    │       ├── architecture.md         ← Architecture document template
    │       ├── runbook.md              ← Runbook/playbook template
    │       ├── adr.md                  ← Architecture decision record template
    │       ├── api-docs.md             ← API documentation template
    │       ├── postmortem.md           ← Incident report template
    │       └── security-review.md      ← Security review template
    └── architecture-diagrams/
        ├── SKILL.md
        └── references/
            ├── flowchart.md            ← Mermaid, PlantUML, Draw.io flowcharts
            ├── sequence.md             ← Sequence diagram patterns
            └── cloud-infra.md          ← Cloud infra diagrams with service icons
```

## Skills

| Skill | Purpose |
|-------|---------|
| **aws-secure-architecture** | Design secure AWS architectures with defense-in-depth (private connectivity, egress control, multi-account, zero-trust) |
| **technical-docs** | Structured documentation with YAML frontmatter — output feeds into docx/pptx/pdf skills |
| **architecture-diagrams** | Diagrams in Mermaid, PlantUML, Draw.io |

## IMPORTANT: All Skills and Agents Go Here

**Every new skill or agent created in any Claude Code session must be added to this marketplace repo.** This is the single source of truth for Maor's custom skills. After adding a skill:
1. Follow the steps below to register it
2. Commit and push to `final-il/maor-skills-marketplace`
3. Install via the marketplace to verify the marketplace config is correct and the skill works

This applies whether working inside this repo or from any other directory.

## How to Add a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add optional `references/` directory for detailed guidance files
3. Update `.claude-plugin/marketplace.json` — add a new entry to the `plugins` array:
   ```json
   {
     "name": "skill-name",
     "description": "What the skill does",
     "source": "./",
     "strict": false,
     "skills": ["./skills/skill-name"]
   }
   ```
4. Update `README.md` with the new skill in the table
5. Commit and push
6. Install via marketplace: run `/plugin` → select "Browse and install plugins" → select `maor-skills-marketplace` → install the new skill
7. Run `/reload-plugins` to activate

## Skill Writing Guide

- **SKILL.md** — Keep under 500 lines. Include YAML frontmatter with `name` and `description`. The description is the primary triggering mechanism — make it specific and slightly "pushy" to avoid under-triggering.
- **references/** — Detailed guidance loaded on demand. Use for templates, patterns, and examples that would bloat the main SKILL.md.
- **Description format** — Include both what the skill does AND specific trigger phrases. Example: "Design secure AWS architectures... Also trigger when the user mentions air-gapped accounts, private endpoints... even if they don't explicitly say 'architecture design.'"

## Design Decisions

- Skills are designed to chain: `aws-secure-architecture` → `architecture-diagrams` → `technical-docs` → docx/pptx/pdf (from Anthropic marketplace)
- `technical-docs` outputs markdown with YAML frontmatter so downstream skills (docx, pptx) know which template to apply
- PlantUML AWS stdlib (`!include <awslib/...>`) is unreliable — the `architecture-diagrams` skill includes both stdlib and plain PlantUML examples as fallback
