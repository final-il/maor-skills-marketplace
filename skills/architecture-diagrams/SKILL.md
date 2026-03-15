---
name: architecture-diagrams
description: "Generate architecture and infrastructure diagrams in Mermaid, PlantUML, and Draw.io formats. Use this skill whenever the user asks to create, generate, or draw a diagram, flowchart, sequence diagram, network diagram, infrastructure diagram, cloud architecture diagram, ER diagram, state diagram, or any visual representation of systems or processes. Also trigger when the user says 'draw this', 'visualize this', 'diagram this', 'make a diagram of', or wants to turn an architecture description into a visual — even if they don't say 'diagram' explicitly."
---

# Architecture Diagram Generator

You generate clear, accurate architecture and infrastructure diagrams in three formats: **Mermaid**, **PlantUML**, and **Draw.io XML**. Each format has different strengths — pick the right one for the user's needs, or ask if unclear.

## Format Selection

| Format | Best For | Renders In |
|--------|----------|-----------|
| **Mermaid** | Flowcharts, sequence diagrams, quick visuals | GitHub, GitLab, Confluence, VS Code, most markdown renderers |
| **PlantUML** | Detailed infra diagrams, network topology, AWS/Azure/GCP with native icons | PlantUML server, IntelliJ, VS Code, Confluence |
| **Draw.io XML** | Complex visual layouts, drag-and-drop editing, presentations | draw.io / diagrams.net (desktop + web) |

**Default**: Mermaid (widest compatibility). If the user needs cloud-provider icons or complex layouts, suggest PlantUML or Draw.io.

If the user doesn't specify a format, produce **Mermaid** and mention the other options. If the diagram is complex (many components, multiple layers), offer PlantUML or Draw.io as alternatives.

## Diagram Types

Read the relevant reference file for syntax patterns and examples.

| Diagram Type | Use Case | Reference |
|-------------|----------|-----------|
| Flowchart / Architecture | System components, data flow, infrastructure | `references/flowchart.md` |
| Sequence Diagram | API calls, request/response flows, auth flows | `references/sequence.md` |
| Network / Cloud Infra | VPCs, subnets, accounts, cloud services with icons | `references/cloud-infra.md` |

## Diagram Principles

1. **Clarity over completeness** — A diagram that shows the important things clearly is better than one that shows everything and is unreadable. If a system has 20 components, show the 6-8 that matter for the story you're telling. Add a note that says "simplified — see [full diagram] for details."

2. **Label everything** — Every arrow needs a label (what data flows, what protocol, what triggers it). Every box needs a name. Unlabeled arrows are the number one source of confusion in architecture diagrams.

3. **Show trust boundaries** — Use subgraphs/boxes/borders to group components by trust level (e.g., "Private Subnet", "Public Internet", "Account A"). This is especially important for security-focused diagrams.

4. **Direction matters** — Data flows should generally go left-to-right or top-to-bottom. Requests go one way, responses come back. Don't mix directions without reason.

5. **Color with purpose** — Use color to convey meaning, not decoration. For example: green for secure/encrypted, red for internet-facing/risky, blue for AWS services, gray for external. Define a legend if using colors.

## Working with Other Skills

This skill works alongside **technical-docs** and **aws-secure-architecture**:

- When **technical-docs** produces an architecture document, this skill generates the diagrams referenced in it.
- When **aws-secure-architecture** designs a solution, this skill can visualize the architecture, data flow, and security controls.

When generating diagrams for another skill's output, match the diagram to the document's audience. Leadership gets simplified high-level views. Engineers get detailed component diagrams.

## Output Format

Always output diagram code in a fenced code block with the correct language identifier:

~~~
```mermaid
graph LR
  A --> B
```
~~~

~~~
```plantuml
@startuml
A -> B
@enduml
```
~~~

For Draw.io, output the XML and tell the user to save it as a `.drawio` file and open it in draw.io/diagrams.net.

When producing multiple diagrams (e.g., a high-level overview + a detailed data flow), clearly label each one with a heading explaining what it shows and when to use it.
