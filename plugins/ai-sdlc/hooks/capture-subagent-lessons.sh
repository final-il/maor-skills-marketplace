#!/usr/bin/env bash
# AI-SDLC self-learning — SubagentStop capture hook (CSI-638, KEYSTONE).
#
# Claude Code does NOT pass a subagent's return text on SubagentStop stdin; it
# passes `transcript_path` (a session JSONL). This hook reconstructs the agent's
# final assistant message from that transcript, scans for a `## Lessons` section,
# parses each `### Lesson` block, and appends one `status:"raw"` event per
# well-formed block to the journal.
#
# Best-effort by contract: any error (toggle off, no transcript, parse failure,
# IO failure, missing jq) results in `exit 0` and at most a warning to the
# sidecar log. This hook MUST NEVER break the pipeline.
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

# jq is required for transcript parsing and JSON emit. If absent, warn + bail.
if ! command -v jq >/dev/null 2>&1; then
  warn "capture-subagent-lessons: jq not found on PATH; skipping capture"
  exit 0
fi

# ---- extract stdin fields --------------------------------------------------
field() {
  printf '%s' "$STDIN_JSON" | jq -r "(.$1 // \"\")" 2>/dev/null || printf ''
}
TRANSCRIPT_PATH="$(field transcript_path)"
AGENT_TYPE="$(field agent_type)"
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  # No transcript to read — nothing to capture. Silent (common case).
  exit 0
fi

# ---- reconstruct final assistant text --------------------------------------
# Take the LAST line whose .type == "assistant", concatenate all
# .message.content[] entries where .type == "text". Guards against a trailing
# non-assistant line (so not literally tail -1).
AGENT_TEXT="$(
  jq -rs '
    [ .[] | select(.type == "assistant") ] as $a
    | if ($a | length) == 0 then ""
      else ($a[-1].message.content // [])
           | map(select(.type == "text") | .text) | join("")
      end
  ' "$TRANSCRIPT_PATH" 2>/dev/null || true
)"

if [ -z "$AGENT_TEXT" ]; then
  exit 0
fi

# ---- parse ## Lessons and append events (shared lib) -----------------------
# The `## Lessons` / `### Lesson` block grammar lives in emit_lessons_from_text
# (lib/journal-append.sh), shared with the PostToolUse/Agent hook (CSI-644).
emit_lessons_from_text "$AGENT_TEXT" "$AGENT_TYPE" "agent-self-report" >/dev/null 2>&1 || true

exit 0
