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
