#!/usr/bin/env bash
# Integration tests for capture-subagent-lessons.sh (CSI-638).
#
# Feeds synthetic transcript JSONL fixtures + stdin payloads through the hook
# and asserts the journal contents. All writes are redirected into a temp dir
# via SDLC_JOURNAL_OVERRIDE / SDLC_LESSONS_FLAG_OVERRIDE — the real journal at
# ~/.claude/... is never touched.
#
# Run:  bash plugins/ai-sdlc/hooks/tests/test_capture_subagent_lessons.sh
# Exit: 0 = all pass, 1 = any failure.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOKS_DIR/capture-subagent-lessons.sh"

PASS=0
FAIL=0

fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok:   %s\n' "$1"; PASS=$((PASS + 1)); }

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then ok "$msg"; else
    fail "$msg (expected='$expected' actual='$actual')"
  fi
}

# Build a transcript JSONL whose last assistant entry carries the given text.
# $1 = output file, $2 = assistant text.
make_transcript() {
  local out="$1" text="$2"
  : >"$out"
  # A user line, then a non-final assistant line, then a final assistant line
  # carrying the lessons text split across two text blocks to exercise join.
  jq -cn '{type:"user", message:{content:[{type:"text", text:"please do the work"}]}}' >>"$out"
  jq -cn '{type:"assistant", message:{content:[{type:"text", text:"intermediate thinking, no lessons here"}]}}' >>"$out"
  jq -cn --arg t "$text" \
    '{type:"assistant", message:{content:[{type:"text", text:"## Summary\nDid the thing.\n\n"},{type:"text", text:$t}]}}' >>"$out"
  # A trailing non-assistant line — the hook must NOT use this one.
  jq -cn '{type:"user", message:{content:[{type:"text", text:"thanks"}]}}' >>"$out"
}

run_hook() {
  # $1 = transcript path, $2 = agent_type
  local tp="$1" agent="$2"
  jq -cn --arg tp "$tp" --arg a "$agent" \
    '{session_id:"s1", transcript_path:$tp, cwd:".", hook_event_name:"SubagentStop", agent_type:$a, agent_id:"a1", stop_hook_active:false}' \
    | bash "$HOOK"
}

WELLFORMED='## Lessons

### Lesson
Trigger: uv invocation failed with an SSL cert error mid-build.
Generalizable rule: Always prefix uv/uvx with SSL_CERT_FILE pointing at the corporate CA bundle.
Suggested fix type: memory-feedback
Suggested target: ~/.claude/.../memory/feedback_uv_ssl.md'

# ===========================================================================
# Test 1: well-formed block → exactly one raw event with correct schema.
# ===========================================================================
T1="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T1/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T1/.disabled"   # absent → enabled
make_transcript "$T1/transcript.jsonl" "$WELLFORMED"
run_hook "$T1/transcript.jsonl" "sdlc-developer"

lines=$(wc -l <"$SDLC_JOURNAL_OVERRIDE" 2>/dev/null | tr -d ' ')
assert_eq "$lines" "1" "well-formed → exactly 1 journal line"

if [ "$lines" = "1" ]; then
  evt="$(tail -1 "$SDLC_JOURNAL_OVERRIDE")"
  assert_eq "$(printf '%s' "$evt" | jq -r .status)" "raw" "status == raw"
  assert_eq "$(printf '%s' "$evt" | jq -r .source)" "agent-self-report" "source == agent-self-report"
  assert_eq "$(printf '%s' "$evt" | jq -r .agent)" "sdlc-developer" "agent == sdlc-developer"
  assert_eq "$(printf '%s' "$evt" | jq -r '.extractor_run')" "null" "extractor_run == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.epic')" "null" "epic == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.story')" "null" "story == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.phase')" "null" "phase == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.applied_commit')" "null" "applied_commit == null"
  # id format
  if printf '%s' "$evt" | jq -r .id | grep -qE '^evt_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9a-f]{6}$'; then
    ok "id matches evt_<date>_<time>_<6hex>"
  else
    fail "id format ($(printf '%s' "$evt" | jq -r .id))"
  fi
  # trigger_summary
  if printf '%s' "$evt" | jq -r .trigger_summary | grep -q 'SSL cert error'; then
    ok "trigger_summary captured"
  else fail "trigger_summary"; fi
  # evidence is verbatim — contains all 4 field labels
  ev="$(printf '%s' "$evt" | jq -r .evidence)"
  if printf '%s' "$ev" | grep -q 'Trigger:' \
     && printf '%s' "$ev" | grep -q 'Generalizable rule:' \
     && printf '%s' "$ev" | grep -q 'Suggested fix type:' \
     && printf '%s' "$ev" | grep -q 'Suggested target:'; then
    ok "evidence contains all 4 verbatim fields"
  else fail "evidence verbatim ($ev)"; fi
fi
rm -rf "$T1"

# ===========================================================================
# Test 2: no ## Lessons section → zero journal lines.
# ===========================================================================
T2="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T2/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T2/.disabled"
make_transcript "$T2/transcript.jsonl" "## Summary
Just did the work, no lessons learned."
run_hook "$T2/transcript.jsonl" "sdlc-tester"
lines=$([ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0)
assert_eq "$lines" "0" "no ## Lessons → 0 journal lines"
rm -rf "$T2"

# ===========================================================================
# Test 3: malformed block (missing Suggested target) → 0 events, >=1 warning.
# ===========================================================================
T3="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T3/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T3/.disabled"
MALFORMED='## Lessons

### Lesson
Trigger: something went sideways.
Generalizable rule: do not do the sideways thing.
Suggested fix type: instruction-edit'
make_transcript "$T3/transcript.jsonl" "$MALFORMED"
run_hook "$T3/transcript.jsonl" "sdlc-developer"
lines=$([ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0)
assert_eq "$lines" "0" "malformed block → 0 journal lines"
wlog="$T3/sdlc-events.warnings.log"
if [ -f "$wlog" ] && grep -q 'malformed' "$wlog"; then
  ok "malformed block → warning logged"
else fail "malformed warning missing"; fi
rm -rf "$T3"

# ===========================================================================
# Test 4: toggle OFF (flag present) → 0 events even with well-formed block.
# ===========================================================================
T4="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T4/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T4/.disabled"
touch "$SDLC_LESSONS_FLAG_OVERRIDE"   # present → disabled
make_transcript "$T4/transcript.jsonl" "$WELLFORMED"
run_hook "$T4/transcript.jsonl" "sdlc-developer"
lines=$([ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0)
assert_eq "$lines" "0" "toggle OFF → 0 journal lines (no-op)"
rm -rf "$T4"

# ===========================================================================
# Test 5: two well-formed blocks → two events; mixed with one malformed → 2.
# ===========================================================================
T5="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T5/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T5/.disabled"
MULTI='## Lessons

### Lesson
Trigger: first friction.
Generalizable rule: first rule.
Suggested fix type: hook
Suggested target: plugins/ai-sdlc/hooks/x.sh

### Lesson
Trigger: malformed one, no target.
Generalizable rule: a rule.
Suggested fix type: script

### Lesson
Trigger: third friction.
Generalizable rule: third rule.
Suggested fix type: skill
Suggested target: plugins/ai-sdlc/skills/y'
make_transcript "$T5/transcript.jsonl" "$MULTI"
run_hook "$T5/transcript.jsonl" "sdlc-architect"
lines=$([ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0)
assert_eq "$lines" "2" "two well-formed + one malformed → 2 journal lines"
rm -rf "$T5"

# ===========================================================================
# Test 6: missing transcript file → 0 events, exit 0 (no crash).
# ===========================================================================
T6="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T6/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T6/.disabled"
run_hook "$T6/does-not-exist.jsonl" "sdlc-developer"
rc=$?
assert_eq "$rc" "0" "missing transcript → exit 0"
lines=$([ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0)
assert_eq "$lines" "0" "missing transcript → 0 journal lines"
rm -rf "$T6"

# ===========================================================================
echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
