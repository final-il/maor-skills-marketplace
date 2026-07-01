# shellcheck shell=bash
# AI-SDLC self-learning — shared hook helpers.
#
# Sourced by the SubagentStop hook (CSI-638) and, later, the UserPromptSubmit
# hook (CSI-639). Pure helpers only — no top-level side effects. Every function
# is best-effort: nothing here may ever cause a non-zero exit in the caller.
#
# Test seams (relied on by CSI-641):
#   SDLC_JOURNAL_OVERRIDE  — if set, journal_path() echoes it instead of the
#                            real journal. Lets tests write to a temp file.
#   SDLC_LESSONS_FLAG_OVERRIDE — if set, lessons_enabled() checks this path for
#                            the disable flag instead of the real one. Lets
#                            tests toggle the hook off without touching ~/.

# memory/ dir that holds the journal, warnings log, and disable flag.
_sdlc_memory_dir() {
  printf '%s' "$HOME/.claude/projects/-Users-maorb-git-dev/memory"
}

# Absolute path of the append-only event journal.
# Honors SDLC_JOURNAL_OVERRIDE (test seam, CSI-641).
journal_path() {
  if [ -n "${SDLC_JOURNAL_OVERRIDE:-}" ]; then
    printf '%s' "$SDLC_JOURNAL_OVERRIDE"
  else
    printf '%s' "$(_sdlc_memory_dir)/sdlc-events.jsonl"
  fi
}

# Absolute path of the hook-readable disable flag. Presence = OFF.
flag_path() {
  if [ -n "${SDLC_LESSONS_FLAG_OVERRIDE:-}" ]; then
    printf '%s' "$SDLC_LESSONS_FLAG_OVERRIDE"
  else
    printf '%s' "$(_sdlc_memory_dir)/.sdlc-lessons-disabled"
  fi
}

# Absolute path of the sidecar warnings log.
warnings_log_path() {
  local jp
  jp="$(journal_path)"
  # Co-locate the warnings log next to the journal so test overrides keep
  # everything inside the temp dir.
  printf '%s' "$(dirname "$jp")/sdlc-events.warnings.log"
}

# Returns 0 (enabled) when the disable flag is absent, non-zero (disabled)
# when it is present. Default ON, matching the design spec.
lessons_enabled() {
  [ ! -e "$(flag_path)" ]
}

# Append a timestamped warning line to the sidecar log. Best-effort.
warn() {
  local msg="$1" log
  log="$(warnings_log_path)"
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >>"$log" 2>/dev/null || true
}

# Generate an event id: evt_<UTC-date>_<HH-MM-SS>_<6hex>.
gen_event_id() {
  local stamp hex
  stamp="$(date -u +%Y-%m-%d_%H-%M-%S)"
  hex="$(openssl rand -hex 3 2>/dev/null)"
  if [ -z "$hex" ]; then
    # Fallback if openssl is unavailable — use $RANDOM-derived hex.
    hex="$(printf '%06x' $(( (RANDOM << 8 | RANDOM) & 0xffffff )))"
  fi
  printf 'evt_%s_%s' "$stamp" "$hex"
}

# Append one already-serialized JSON object (single line) to the journal.
# Creates the parent dir if needed. Returns non-zero on IO failure so the
# caller can warn; the caller must still exit 0.
append_event_json() {
  local line="$1" jp
  jp="$(journal_path)"
  mkdir -p "$(dirname "$jp")" 2>/dev/null || return 1
  printf '%s\n' "$line" >>"$jp" 2>/dev/null || return 1
  return 0
}

# Parse a `## Lessons` section out of an assistant/agent message and append one
# raw event per well-formed `### Lesson` block. Shared by the SubagentStop hook
# (CSI-638) and the PostToolUse/Agent hook (CSI-644) so the block grammar lives
# in exactly one place.
#
# Args:  $1 = full message text, $2 = agent label, $3 = source
#        ("agent-self-report" | "agent-tool-return")
# Echoes: "<emitted> <malformed>" counts. Never returns non-zero.
# Requires jq (caller must have verified it). Best-effort throughout.
emit_lessons_from_text() {
  local agent_text="$1" agent="$2" source="$3"
  local emitted=0 malformed=0

  [ -z "$agent_text" ] && { printf '0 0'; return 0; }

  # Must contain a line-anchored `## Lessons` header.
  if ! printf '%s\n' "$agent_text" | grep -qE '^## Lessons[[:space:]]*$'; then
    printf '0 0'; return 0
  fi

  # Slice from the ## Lessons header to the next H2 (or end-of-text).
  local lessons_body
  lessons_body="$(
    printf '%s\n' "$agent_text" | awk '
      /^## Lessons[[:space:]]*$/ { capture = 1; next }
      capture && /^## / { capture = 0 }
      capture { print }
    '
  )"
  [ -z "$lessons_body" ] && { printf '0 0'; return 0; }

  # Read one field value by line-prefix from a block of text. Tolerates an
  # optional leading list marker ("- ", "* ") and leading whitespace, since
  # agents emit fields as "- Trigger: ..." bullets.
  _elt_field() {
    printf '%s\n' "$1" \
      | grep -m1 -E "^[[:space:]]*[-*]?[[:space:]]*${2}:" \
      | sed -E "s/^[[:space:]]*[-*]?[[:space:]]*${2}:[[:space:]]*//" \
      | sed -E 's/[[:space:]]+$//'
  }

  # Split into blocks delimited by ^### Lesson, using \036 as a record sentinel.
  local blocks
  blocks="$(
    printf '%s\n' "$lessons_body" | awk '
      /^### Lesson([[:space:]].*)?$/ {
        if (started) print "\036";
        started = 1
      }
      started { print }
      END { if (started) print "\036" }
    '
  )"

  local block trigger rule fixtype target evidence evt_id ts line
  local OLD_IFS="$IFS"
  while IFS= read -r -d $'\036' block; do
    [ -z "${block//[$'\n\t ']/}" ] && continue

    trigger="$(_elt_field "$block" 'Trigger')"
    rule="$(_elt_field "$block" 'Generalizable rule')"
    fixtype="$(_elt_field "$block" 'Suggested fix type')"
    target="$(_elt_field "$block" 'Suggested target')"

    if [ -z "$trigger" ] || [ -z "$rule" ] || [ -z "$fixtype" ] || [ -z "$target" ]; then
      malformed=$((malformed + 1))
      warn "emit_lessons_from_text: skipped malformed ### Lesson block (agent=$agent source=$source; missing one of Trigger/Generalizable rule/Suggested fix type/Suggested target)"
      continue
    fi

    evidence="$(printf '%s' "$block" | sed -E 's/[[:space:]]+$//')"
    evt_id="$(gen_event_id)"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    line="$(
      jq -cn \
        --arg id "$evt_id" \
        --arg ts "$ts" \
        --arg agent "$agent" \
        --arg source "$source" \
        --arg trigger "$trigger" \
        --arg evidence "$evidence" \
        '{
          id: $id,
          ts: $ts,
          epic: null,
          story: null,
          phase: null,
          agent: $agent,
          source: $source,
          trigger_summary: $trigger,
          evidence: $evidence,
          extractor_run: null,
          status: "raw",
          applied_commit: null
        }' 2>/dev/null || true
    )"

    if [ -z "$line" ]; then
      warn "emit_lessons_from_text: jq failed to serialize event (agent=$agent source=$source)"
      continue
    fi

    if append_event_json "$line"; then
      emitted=$((emitted + 1))
    else
      warn "emit_lessons_from_text: journal append failed (agent=$agent source=$source); event dropped"
    fi
  done <<EOF
$blocks
EOF
  IFS="$OLD_IFS"

  printf '%s %s' "$emitted" "$malformed"
}
