#!/usr/bin/env bash
# AI-SDLC self-learning — PostToolUse/Agent capture hook (CSI-644).
#
# WHY THIS EXISTS (vs. the SubagentStop hook, CSI-638):
#   /sdlc spawns every sub-agent via the `Agent` tool and never sets
#   `subagent_type` (plugin subagents can't reach the MCP/Jira tools they need).
#   `SubagentStop` fires only for the Task tool's typed subagents — so it NEVER
#   fires for /sdlc's agents, and their `## Lessons` blocks were never captured.
#
#   `PostToolUse` on the `Agent` matcher DOES fire when an Agent() call returns.
#   Its stdin payload carries the agent's full return under
#   `.tool_response.content` — a standard content-block array; the text is in
#   the block(s) where `.type == "text"`. This is the canonical return value
#   (not a mid-transcript slice), so it's more reliable than reconstructing the
#   final assistant message from a transcript.
#
# Best-effort by contract: any error (toggle off, missing jq, no content, parse
# failure, IO failure) results in `exit 0` and at most a sidecar-log warning.
# This hook MUST NEVER break the pipeline.
#
# NOT `set -e` — a hard abort would defeat the fail-safe guarantee.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/journal-append.sh
. "$SCRIPT_DIR/lib/journal-append.sh" || exit 0

# ---- read stdin payload ----------------------------------------------------
STDIN_JSON="$(cat 2>/dev/null || true)"

# Toggle gate: if disabled, no-op immediately.
if ! lessons_enabled; then
  exit 0
fi

# jq is required for payload parsing and JSON emit.
if ! command -v jq >/dev/null 2>&1; then
  warn "capture-agent-lessons: jq not found on PATH; skipping capture"
  exit 0
fi

# Only handle the Agent tool. (The matcher should already scope this, but guard
# in case the hook is wired more broadly.)
TOOL_NAME="$(printf '%s' "$STDIN_JSON" | jq -r '(.tool_name // "")' 2>/dev/null || printf '')"
if [ "$TOOL_NAME" != "Agent" ]; then
  exit 0
fi

# ---- extract the agent's return text ---------------------------------------
# .tool_response.content is a content-block array; concatenate the text blocks.
AGENT_TEXT="$(
  printf '%s' "$STDIN_JSON" \
    | jq -r '(.tool_response.content // []) | map(select(.type == "text") | .text) | join("")' \
      2>/dev/null || true
)"

if [ -z "$AGENT_TEXT" ]; then
  exit 0
fi

# Label the event by the resolved agentType when present (e.g. sdlc-developer).
AGENT_TYPE="$(
  printf '%s' "$STDIN_JSON" \
    | jq -r '(.tool_response.agentType // .tool_input.subagent_type // "")' 2>/dev/null || printf ''
)"
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

# ---- parse ## Lessons and append events (shared lib) -----------------------
emit_lessons_from_text "$AGENT_TEXT" "$AGENT_TYPE" "agent-tool-return" >/dev/null 2>&1 || true

exit 0
