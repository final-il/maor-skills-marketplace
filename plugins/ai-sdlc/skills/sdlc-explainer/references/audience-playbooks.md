# Audience Playbooks — reshaping the explanation per reader

The same AI-SDLC survey digest serves very different readers. The wrong altitude wastes a newcomer's time or insults a contributor's. Before explaining, figure out **who is asking and why**, then use the matching playbook to decide what to include, what to cut, and which diagrams to lead with.

If you can't tell which reader you're facing, ask one question: *"Are you trying to use AI-SDLC, operate a run of it, or modify how it works?"* The answer selects the playbook.

All three playbooks draw from the **same** Step-1 survey — they differ only in depth, ordering, and which diagrams lead. Never hardcode facts; derive them from source as always.

---

## Playbook A — First-time user ("what is this, how do I use it?")

**Goal:** an accurate mental model in the shortest honest path, plus enough to press the button.

**Lead with:** the whole-system mind map (cookbook §1), then the phase flowchart (§2).

**Include:**
- One paragraph on the idea — what problem it solves and the message-bus concept.
- The 2–3 most load-bearing principles (especially any "orchestrator never does the work itself" rule — a newcomer must not expect to chat with a coder; they're driving a pipeline).
- The phase flow as a picture, with a one-sentence gloss per phase. Names from the survey.
- **The human gates, front and center** — the exact moments the pipeline stops and waits for them. This is what they'll actually experience, so make it concrete: "you'll be asked to approve X before Y."
- The entry points: how to start a new project, how to resume, and any modes — as the survey found them.

**Cut:** the artifact-discipline contract, the spawn protocol, per-agent internals, the self-learning mechanics. A user doesn't need to know how agents are spawned to use the system.

**Tone:** plain. Avoid jargon like "verdict routing"; say "the plan gets a review, and if it has serious problems it goes back for a rewrite before you ever see it."

---

## Playbook B — Operator ("I'm running this on a real project")

**Goal:** confidently drive a live run, recognize each state, and know what to do at every pause or failure.

**Lead with:** the phase flowchart (§2) annotated with gates, then the Jira state machine (§4) so they can read a board and know where things stand.

**Include:**
- The full phase list with, per phase: who runs it, what it produces, and how to tell it succeeded (the artifact header it posts, the status it moves to). All from the survey.
- **Every decision point** (cookbook §5) — the verdicts, the pass/fail gates, and especially the **retry caps and human-escalation exits**. An operator needs to know when the pipeline will stop and ask them, and what "flagged for human review" means.
- The story lifecycle sequence (§3) with the defect detour, so they recognize the bug loop when it happens on their board.
- Resume / handoff / pause behavior — how to stop and continue a run safely.
- The merge/completion behavior and any promotion gate (dev→main or equivalent) — what they'll be asked to approve at the end.
- Failure modes: what each "stop and ask" looks like and the recommended response.

**Cut:** how agents are authored, the frontmatter format, the internal spawn-prompt structure. An operator consumes the pipeline; they don't edit it.

**Tone:** operational and specific. Use the real status names and artifact headers verbatim — they'll be looking at exactly those strings in Jira.

---

## Playbook C — Contributor ("I want to modify or add an agent / phase")

**Goal:** understand the system deeply enough to change it without breaking coordination.

**Lead with:** the coordination model (cookbook §6), then the phase flowchart (§2) — a contributor thinks in terms of the contract between components.

**Include:**
- The **coordination contract** in full: how the orchestrator spawns agents, what a context block contains, the "read only your named artifacts / write exactly one artifact" discipline, and why it exists (context economy). Pull specifics from the conventions skill and the context-protocol reference in the survey.
- The agent anatomy: what a role file contains, how model tiers are assigned, how an agent declares what it reads/writes/decides. Point at real agent files by path.
- Workspace isolation mechanics (worktrees or whatever the survey found) — because a new code-touching agent must respect them.
- The decision/verdict contracts (§5) — if they're adding a phase, they need to know how routing verdicts are consumed by the orchestrator.
- Cross-cutting systems (self-learning, resume) and the hooks/scripts that support them, if the change touches them.
- **Where the source of truth lives** (the survey's file map) and the rule that behavior is defined in the orchestrator + agent files — so their change lands in the right place.
- Any governance rules the survey found for adding/promoting agents (validity tests, graduation rules).

**Cut:** nothing about internals is too deep — but still lead with structure, not a file dump. Give them the map and the contracts; let them read the files themselves via the cited paths.

**Tone:** precise, contract-oriented. Cite `file:line` liberally — a contributor will open every file you mention.

---

## Cross-playbook rules

- **One survey, three views.** Run the survey once; reshape. Don't re-derive facts per audience.
- **Diagrams scale with depth.** A user gets 1–2 diagrams; an operator 3–4; a contributor as many as clarify the contracts. More isn't always better — each diagram must earn its place.
- **Gates are universal.** All three readers care about the human-approval pauses, at different depths. Never drop them.
- **Honesty doesn't flex by audience.** You simplify *language and depth* for a newcomer; you never simplify away a loop, a cap, or a gate. Omitting the bug loop to make the picture cleaner misleads every reader equally.
