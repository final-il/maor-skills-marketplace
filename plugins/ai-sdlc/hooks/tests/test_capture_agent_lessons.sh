#!/usr/bin/env bash
# Integration tests for capture-agent-lessons.sh (CSI-644).
#
# WHY: /sdlc spawns every sub-agent via the `Agent` tool (never `subagent_type`),
# so SubagentStop never fires for it. This PostToolUse/Agent hook reads the
# agent's return text from the canonical `.tool_response.content` content-block
# array. These tests feed synthetic PostToolUse payloads through the hook and
# assert the journal contents. All writes redirect to a temp dir via
# SDLC_JOURNAL_OVERRIDE / SDLC_LESSONS_FLAG_OVERRIDE — the real journal is never
# touched.
#
# Run:  bash plugins/ai-sdlc/hooks/tests/test_capture_agent_lessons.sh
# Exit: 0 = all pass, 1 = any failure.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOKS_DIR/capture-agent-lessons.sh"

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

jlines() {
  local jp="$1"
  if [ -f "$jp" ]; then wc -l <"$jp" | tr -d ' '; else echo 0; fi
}

# Run the hook with a PostToolUse/Agent payload carrying $2 as the agent's
# returned text (in .tool_response.content[0].text). $1 = agentType.
run_hook() {
  local agent_type="$1" text="$2"
  jq -cn --arg at "$agent_type" --arg t "$text" \
    '{tool_name:"Agent",
      tool_input:{prompt:"do the work"},
      tool_response:{status:"completed", agentType:$at,
        content:[{type:"text", text:$t}]}}' \
    | bash "$HOOK"
}

# Agents emit lesson fields as "- Trigger:" bullets (real-world shape from the
# PostToolUse payload probe), so exercise the list-marker grammar explicitly.
WELLFORMED='Here is my final answer.

## Lessons

### Lesson
- Trigger: uv invocation failed with an SSL cert error mid-build.
- Generalizable rule: Always prefix uv/uvx with SSL_CERT_FILE pointing at the corporate CA bundle.
- Suggested fix type: memory-feedback
- Suggested target: ~/.claude/.../memory/feedback_uv_ssl.md'

# ===========================================================================
# Test 1: well-formed block (bullet fields) → exactly one raw event, schema OK.
# ===========================================================================
T1="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T1/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T1/.disabled"
run_hook "ai-sdlc:sdlc-developer" "$WELLFORMED"
rc=$?
assert_eq "$rc" "0" "well-formed → exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "1" "well-formed (bullet fields) → exactly 1 journal line"
if [ "$(jlines "$SDLC_JOURNAL_OVERRIDE")" = "1" ]; then
  evt="$(tail -1 "$SDLC_JOURNAL_OVERRIDE")"
  assert_eq "$(printf '%s' "$evt" | jq -r .status)" "raw" "status == raw"
  assert_eq "$(printf '%s' "$evt" | jq -r .source)" "agent-tool-return" "source == agent-tool-return"
  assert_eq "$(printf '%s' "$evt" | jq -r .agent)" "ai-sdlc:sdlc-developer" "agent == resolved agentType"
  assert_eq "$(printf '%s' "$evt" | jq -r .epic)" "null" "epic == null"
  assert_eq "$(printf '%s' "$evt" | jq -r .extractor_run)" "null" "extractor_run == null"
  if printf '%s' "$evt" | jq -r .id | grep -qE '^evt_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9a-f]{6}$'; then
    ok "id matches evt_<date>_<time>_<6hex>"
  else fail "id format ($(printf '%s' "$evt" | jq -r .id))"; fi
  if printf '%s' "$evt" | jq -r .trigger_summary | grep -q 'SSL cert error'; then
    ok "trigger_summary captured"
  else fail "trigger_summary"; fi
  # Schema parity with CSI-638/639.
  keys="$(printf '%s' "$evt" | jq -cS 'keys')"
  assert_eq "$keys" '["agent","applied_commit","epic","evidence","extractor_run","id","phase","source","status","story","trigger_summary","ts"]' "exact 12-field schema"
fi
rm -rf "$T1"

# ===========================================================================
# Test 2: non-Agent tool → 0 events (guard against broad wiring).
# ===========================================================================
T2="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T2/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T2/.disabled"
jq -cn --arg t "$WELLFORMED" \
  '{tool_name:"Bash", tool_response:{content:[{type:"text", text:$t}]}}' | bash "$HOOK"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "non-Agent tool → 0 events"
rm -rf "$T2"

# ===========================================================================
# Test 3: no ## Lessons → 0 events.
# ===========================================================================
T3="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T3/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T3/.disabled"
run_hook "ai-sdlc:sdlc-tester" "Just an answer, nothing to report."
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "no ## Lessons → 0 events"
rm -rf "$T3"

# ===========================================================================
# Test 4: malformed block (missing Suggested target) → 0 events + warning.
# ===========================================================================
T4="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T4/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T4/.disabled"
run_hook "ai-sdlc:sdlc-developer" "## Lessons

### Lesson
- Trigger: something went sideways.
- Generalizable rule: do not do the sideways thing.
- Suggested fix type: instruction-edit"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "malformed block → 0 events"
if [ -f "$T4/sdlc-events.warnings.log" ] && grep -q 'malformed' "$T4/sdlc-events.warnings.log"; then
  ok "malformed block → warning logged"
else fail "malformed warning missing"; fi
rm -rf "$T4"

# ===========================================================================
# Test 5: two well-formed + one malformed → exactly 2 events.
# ===========================================================================
T5="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T5/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T5/.disabled"
run_hook "ai-sdlc:sdlc-architect" "## Lessons

### Lesson
- Trigger: first friction.
- Generalizable rule: first rule.
- Suggested fix type: hook
- Suggested target: plugins/ai-sdlc/hooks/x.sh

### Lesson
- Trigger: malformed one, no target.
- Generalizable rule: a rule.
- Suggested fix type: script

### Lesson
- Trigger: third friction.
- Generalizable rule: third rule.
- Suggested fix type: skill
- Suggested target: plugins/ai-sdlc/skills/y"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "2" "two well-formed + one malformed → 2 events"
rm -rf "$T5"

# ===========================================================================
# Test 6: toggle OFF (flag present) → 0 events even on well-formed block.
# ===========================================================================
T6="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T6/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T6/.disabled"
touch "$SDLC_LESSONS_FLAG_OVERRIDE"
run_hook "ai-sdlc:sdlc-developer" "$WELLFORMED"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "toggle OFF → 0 events (no-op)"
rm -rf "$T6"

# ===========================================================================
# Test 7: multi-block content array (text split across two content blocks) →
# text is joined, lesson still parsed.
# ===========================================================================
T7="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T7/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T7/.disabled"
BLOCK_A='Some preamble.

## Lessons

### Lesson
- Trigger: split-block friction.
'
BLOCK_B='- Generalizable rule: joins across content blocks.
- Suggested fix type: instruction
- Suggested target: CLAUDE.md'
jq -cn \
  --arg a "$BLOCK_A" \
  --arg b "$BLOCK_B" \
  '{tool_name:"Agent", tool_response:{agentType:"ai-sdlc:sdlc-developer",
    content:[{type:"text", text:$a},{type:"text", text:$b}]}}' | bash "$HOOK"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "1" "text joined across content blocks → 1 event"
rm -rf "$T7"

# ===========================================================================
# Test 8: missing/empty content → 0 events, exit 0.
# ===========================================================================
T8="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T8/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T8/.disabled"
printf '%s' '{"tool_name":"Agent","tool_response":{"status":"completed"}}' | bash "$HOOK"
rc=$?
assert_eq "$rc" "0" "missing content → exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "missing content → 0 events"
rm -rf "$T8"

# ===========================================================================
# Test 9 (hooks.json): PostToolUse wired to capture-agent-lessons on Agent, and
# SubagentStop (CSI-638) + UserPromptSubmit (CSI-639) left intact.
# ===========================================================================
HOOKS_JSON="$HOOKS_DIR/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  ok "hooks.json exists"
  if jq -e '.hooks.PostToolUse' "$HOOKS_JSON" >/dev/null 2>&1; then
    ok "hooks.json: PostToolUse key present"
  else fail "hooks.json: PostToolUse key missing"; fi
  if jq -r '.hooks.PostToolUse[] | select(.matcher=="Agent") | .hooks[0].command' "$HOOKS_JSON" 2>/dev/null | grep -q 'capture-agent-lessons'; then
    ok "hooks.json: PostToolUse/Agent references capture-agent-lessons"
  else fail "hooks.json: PostToolUse/Agent command wrong"; fi
  if jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOOKS_JSON" 2>/dev/null | grep -q 'capture-subagent-lessons'; then
    ok "hooks.json: SubagentStop (CSI-638) left intact"
  else fail "hooks.json: SubagentStop entry disturbed"; fi
  if jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS_JSON" 2>/dev/null | grep -q 'capture-user-correction'; then
    ok "hooks.json: UserPromptSubmit (CSI-639) left intact"
  else fail "hooks.json: UserPromptSubmit entry disturbed"; fi
else
  fail "hooks.json not found at $HOOKS_JSON"
fi

# ===========================================================================
echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
