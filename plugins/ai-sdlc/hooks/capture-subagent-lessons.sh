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

# ---- scan for ## Lessons ----------------------------------------------------
# Case-sensitive, line-anchored.
if ! printf '%s\n' "$AGENT_TEXT" | grep -qE '^## Lessons[[:space:]]*$'; then
  exit 0
fi

# Slice from the ## Lessons header to end-of-text.
LESSONS_BODY="$(
  printf '%s\n' "$AGENT_TEXT" | awk '
    /^## Lessons[[:space:]]*$/ { capture = 1; next }
    capture && /^## / { capture = 0 }   # next H2 ends the Lessons section
    capture { print }
  '
)"

if [ -z "$LESSONS_BODY" ]; then
  exit 0
fi

# ---- parse each ### Lesson block -------------------------------------------
# Read one field value by line-prefix from a block of text.
extract_field() {
  local block="$1" prefix="$2"
  printf '%s\n' "$block" \
    | grep -m1 -E "^${prefix}:" \
    | sed -E "s/^${prefix}:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

# Split LESSONS_BODY into blocks on lines matching ^### Lesson.
# Each block is the ### Lesson header line plus following lines up to the next
# ### Lesson (or end).
emitted=0
malformed=0

# Use awk to emit each block delimited by a NUL-safe sentinel.
BLOCKS="$(
  printf '%s\n' "$LESSONS_BODY" | awk '
    /^### Lesson([[:space:]].*)?$/ {
      if (started) print "\036";   # RS sentinel between blocks
      started = 1
    }
    started { print }
    END { if (started) print "\036" }
  '
)"

# Iterate blocks split on the \036 (record separator) sentinel.
OLD_IFS="$IFS"
while IFS= read -r -d $'\036' block; do
  [ -z "${block//[$'\n\t ']/}" ] && continue   # skip empty/whitespace block

  trigger="$(extract_field "$block" 'Trigger')"
  rule="$(extract_field "$block" 'Generalizable rule')"
  fixtype="$(extract_field "$block" 'Suggested fix type')"
  target="$(extract_field "$block" 'Suggested target')"

  # Malformed: any of the 4 fields missing/empty → skip with warning.
  if [ -z "$trigger" ] || [ -z "$rule" ] || [ -z "$fixtype" ] || [ -z "$target" ]; then
    malformed=$((malformed + 1))
    warn "capture-subagent-lessons: skipped malformed ### Lesson block (agent=$AGENT_TYPE; missing one of Trigger/Generalizable rule/Suggested fix type/Suggested target)"
    continue
  fi

  evidence="$(printf '%s' "$block" | sed -E 's/[[:space:]]+$//')"
  evt_id="$(gen_event_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Build the event with jq so all values are correctly JSON-escaped.
  line="$(
    jq -cn \
      --arg id "$evt_id" \
      --arg ts "$ts" \
      --arg agent "$AGENT_TYPE" \
      --arg trigger "$trigger" \
      --arg evidence "$evidence" \
      '{
        id: $id,
        ts: $ts,
        epic: null,
        story: null,
        phase: null,
        agent: $agent,
        source: "agent-self-report",
        trigger_summary: $trigger,
        evidence: $evidence,
        extractor_run: null,
        status: "raw",
        applied_commit: null
      }' 2>/dev/null || true
  )"

  if [ -z "$line" ]; then
    warn "capture-subagent-lessons: jq failed to serialize event (agent=$AGENT_TYPE)"
    continue
  fi

  if append_event_json "$line"; then
    emitted=$((emitted + 1))
  else
    warn "capture-subagent-lessons: journal append failed (agent=$AGENT_TYPE); event dropped"
  fi
done <<EOF
$BLOCKS
EOF
IFS="$OLD_IFS"

exit 0
