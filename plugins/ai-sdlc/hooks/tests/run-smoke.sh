#!/usr/bin/env bash
# CSI-641 — Phase D smoke verification for the hook-based capture loop.
#
# This is the QA-DISTRUST verification gate for the whole self-learning capture
# loop (epic CSI-634). It does NOT trust agent/QA reports — every assertion
# reads the actual journal file and inspects it with `jq`.
#
# What it verifies (Layer A — deterministic, no model, no /sdlc session):
#   1. SubagentStop against a REAL /sdlc transcript (byte-identical copy of an
#      actual plan-challenger run that emitted a `## Lessons` block). Asserts a
#      well-formed status:"raw", source:"agent-self-report" event with the full
#      12-field schema and verbatim evidence. (CUJ keystone — validates the
#      transcript-extraction contract against real data, not a hand-built fixture.)
#   2. hook-fires-without-model (N4): capture-user-correction.sh end-to-end with
#      a STUBBED classifier (SDLC_CLASSIFIER_STUB=yes) lands a source:"user-
#      correction", status:"raw" event with NO main model in the loop. Re-run
#      with the stub forced to "no", and with a non-correction prompt through the
#      REAL keyword pre-filter (no API key) — both write NOTHING. Confirms the
#      emitted schema has NO `classifier` field (CSI-644 as-built contract).
#   3. toggle hard-gate: with the .sdlc-lessons-disabled flag present, BOTH hooks
#      write nothing and exit 0.
#   4. schema / robustness: malformed transcript, missing ## Lessons, multiple
#      ### Lesson blocks → correct count/skip behavior; hooks always exit 0.
#
# Isolation: every journal goes to a temp path (mktemp); the real journal at
# ~/.claude/.../sdlc-events.jsonl is NEVER touched. Flag file is overridden via
# SDLC_LESSONS_FLAG_OVERRIDE. Classifier is stubbed so no network call is made.
#
# bash 3.2 compatible (macOS system bash) — no mapfile, no `read -d`.
#
# Run:  bash plugins/ai-sdlc/hooks/tests/run-smoke.sh
# Exit: 0 = all pass, 1 = any failure.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$HOOKS_DIR/tests"
FIXTURES_DIR="$TESTS_DIR/fixtures"
SUBAGENT_HOOK="$HOOKS_DIR/capture-subagent-lessons.sh"
CORRECTION_HOOK="$HOOKS_DIR/capture-user-correction.sh"
REAL_FIXTURE="$FIXTURES_DIR/real-subagent-transcript.jsonl"

# The literal real source this fixture was copied from (documented, for audit).
REAL_SOURCE_PATH="/Users/maorb/.claude/projects/-Users-maorb-git-dev/52f55015-9148-4180-8c03-a92b81743323/subagents/agent-afd47cdc299c81709.jsonl"

PASS=0
FAIL=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok:   %s\n' "$1"; PASS=$((PASS + 1)); }

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then ok "$msg"; else
    fail "$msg (expected='$expected' actual='$actual')"
  fi
}

# Line count of a journal file, 0 if absent.
jlines() {
  local jp="$1"
  if [ -f "$jp" ]; then wc -l <"$jp" | tr -d ' '; else echo 0; fi
}

# Fresh isolated temp env per scenario. Sets SCN_DIR / JOURNAL / FLAG and
# clears any classifier/key state. Caller may then set SDLC_CLASSIFIER_STUB etc.
new_scenario() {
  SCN_DIR="$(mktemp -d "$TMP_ROOT/scn.XXXXXX")"
  export SDLC_JOURNAL_OVERRIDE="$SCN_DIR/journal.jsonl"
  export SDLC_LESSONS_FLAG_OVERRIDE="$SCN_DIR/.sdlc-lessons-disabled"  # absent => enabled
  unset SDLC_CLASSIFIER_STUB 2>/dev/null || true
  # Ensure no real key leaks a live classifier call into a smoke run.
  unset ANTHROPIC_API_KEY 2>/dev/null || true
}

# Run the SubagentStop hook with a given transcript + agent_type.
run_subagent_hook() {
  local tp="$1" agent="$2"
  jq -cn --arg tp "$tp" --arg a "$agent" \
    '{session_id:"smoke", transcript_path:$tp, cwd:".", hook_event_name:"SubagentStop", agent_type:$a, agent_id:"a1", stop_hook_active:false}' \
    | bash "$SUBAGENT_HOOK"
}

# Run the UserPromptSubmit hook with a given prompt + optional transcript path.
run_correction_hook() {
  local prompt="$1" tp="${2:-}"
  jq -cn --arg p "$prompt" --arg tp "$tp" \
    '{session_id:"smoke", transcript_path:$tp, cwd:".", hook_event_name:"UserPromptSubmit", prompt:$p}' \
    | bash "$CORRECTION_HOOK"
}

# The exact 12-field schema (sorted keys) every raw event must have.
EXPECTED_KEYS='agent
applied_commit
epic
evidence
extractor_run
id
phase
source
status
story
trigger_summary
ts'

assert_schema() {
  local evt="$1" label="$2"
  local got
  got="$(printf '%s' "$evt" | jq -r 'keys_unsorted | sort | .[]' 2>/dev/null)"
  assert_eq "$got" "$EXPECTED_KEYS" "$label: exact 12-field schema"
  # CSI-644 as-built contract: NO classifier field on the emitted event.
  if printf '%s' "$evt" | jq -e 'has("classifier")' >/dev/null 2>&1; then
    fail "$label: event unexpectedly has a 'classifier' field (CSI-644 contract violated)"
  else
    ok "$label: no 'classifier' field (CSI-644 as-built contract)"
  fi
}

echo "================================================================"
echo " CSI-641 Phase D smoke verification (QA-distrust gate)"
echo " Real transcript fixture: $REAL_FIXTURE"
echo " Copied byte-identical from: $REAL_SOURCE_PATH"
echo "================================================================"
echo

# Sanity: the real fixture must be present and committed.
if [ ! -f "$REAL_FIXTURE" ]; then
  fail "SCENARIO 1 precondition: real transcript fixture missing at $REAL_FIXTURE"
  echo; printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 1
else
  ok "real transcript fixture present ($(wc -l <"$REAL_FIXTURE" | tr -d ' ') lines)"
fi

# ===========================================================================
# SCENARIO 1 — SubagentStop against a REAL /sdlc transcript.
# The fixture is a byte-identical copy of an actual plan-challenger run that
# returned a `## Lessons` block. This validates the .type=="assistant" /
# message.content[].type=="text" extraction against REAL data (the risk CSI-638
# flagged), not a hand-built fixture.
# ===========================================================================
echo "--- SCENARIO 1: SubagentStop vs REAL transcript ---"
new_scenario
run_subagent_hook "$REAL_FIXTURE" "sdlc-plan-challenger"
rc=$?
assert_eq "$rc" "0" "S1: hook exits 0"
n="$(jlines "$SDLC_JOURNAL_OVERRIDE")"
assert_eq "$n" "1" "S1: real transcript with one ## Lessons block => exactly 1 raw event"
if [ "$n" = "1" ]; then
  evt="$(tail -1 "$SDLC_JOURNAL_OVERRIDE")"
  assert_eq "$(printf '%s' "$evt" | jq -r .status)" "raw" "S1: status == raw"
  assert_eq "$(printf '%s' "$evt" | jq -r .source)" "agent-self-report" "S1: source == agent-self-report"
  assert_eq "$(printf '%s' "$evt" | jq -r .agent)" "sdlc-plan-challenger" "S1: agent == sdlc-plan-challenger"
  assert_eq "$(printf '%s' "$evt" | jq -r .epic)" "null" "S1: epic == null"
  assert_eq "$(printf '%s' "$evt" | jq -r .applied_commit)" "null" "S1: applied_commit == null"
  assert_schema "$evt" "S1"
  # id format
  if printf '%s' "$evt" | jq -r .id | grep -qE '^evt_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9a-f]{6}$'; then
    ok "S1: id matches evt_<date>_<time>_<6hex>"
  else
    fail "S1: id format ($(printf '%s' "$evt" | jq -r .id))"
  fi
  # Verbatim evidence: must contain all 4 field labels from the REAL lesson and
  # the real lesson's distinctive text (proves verbatim capture, not synthesis).
  ev="$(printf '%s' "$evt" | jq -r .evidence)"
  if printf '%s' "$ev" | grep -q 'Trigger:' \
     && printf '%s' "$ev" | grep -q 'Generalizable rule:' \
     && printf '%s' "$ev" | grep -q 'Suggested fix type:' \
     && printf '%s' "$ev" | grep -q 'Suggested target:'; then
    ok "S1: evidence contains all 4 verbatim Lesson field labels"
  else
    fail "S1: evidence missing verbatim field labels"
  fi
  if printf '%s' "$ev" | grep -q 'sdlc-plan-challenger.md'; then
    ok "S1: evidence is verbatim from the real lesson (distinctive target text present)"
  else
    fail "S1: evidence does not contain the real lesson's distinctive text"
  fi
  if printf '%s' "$evt" | jq -r .trigger_summary | grep -qi 'Bedrock'; then
    ok "S1: trigger_summary captured from real lesson"
  else
    fail "S1: trigger_summary not captured from real lesson"
  fi
fi
echo

# ===========================================================================
# SCENARIO 2 — hook-fires-without-model (the N4 assertion).
# capture-user-correction.sh runs end-to-end. The classifier is STUBBED so NO
# main model and NO network are in the loop; the hook decides and writes alone.
# ===========================================================================
echo "--- SCENARIO 2: hook fires without the model (N4) ---"

# 2a: stubbed classifier = yes => exactly one user-correction raw event.
new_scenario
export SDLC_CLASSIFIER_STUB="yes"
run_correction_hook "you should always use git -C instead of cd && git" ""
rc=$?
assert_eq "$rc" "0" "S2a: hook exits 0"
n="$(jlines "$SDLC_JOURNAL_OVERRIDE")"
assert_eq "$n" "1" "S2a: stub=yes => exactly 1 raw event (no model, no network)"
if [ "$n" = "1" ]; then
  evt="$(tail -1 "$SDLC_JOURNAL_OVERRIDE")"
  assert_eq "$(printf '%s' "$evt" | jq -r .source)" "user-correction" "S2a: source == user-correction"
  assert_eq "$(printf '%s' "$evt" | jq -r .status)" "raw" "S2a: status == raw"
  assert_eq "$(printf '%s' "$evt" | jq -r .agent)" "null" "S2a: agent == null (user-correction)"
  assert_schema "$evt" "S2a"
  ev="$(printf '%s' "$evt" | jq -r .evidence)"
  if printf '%s' "$ev" | grep -q 'USER: you should always use git -C'; then
    ok "S2a: evidence captures verbatim user message"
  else
    fail "S2a: evidence does not capture the verbatim user message"
  fi
fi

# 2b: stubbed classifier = no => NO event written.
new_scenario
export SDLC_CLASSIFIER_STUB="no"
run_correction_hook "you should always use git -C instead of cd && git" ""
n="$(jlines "$SDLC_JOURNAL_OVERRIDE")"
assert_eq "$n" "0" "S2b: stub=no => 0 events (classifier veto honored)"

# 2c: non-correction prompt through the REAL keyword pre-filter (no stub, no
# API key). The pre-filter must bail BEFORE any classifier call => 0 events.
new_scenario   # clears stub + key
run_correction_hook "Please summarize the architecture of the jiralyzer project." ""
rc=$?
assert_eq "$rc" "0" "S2c: hook exits 0 on ordinary prompt"
n="$(jlines "$SDLC_JOURNAL_OVERRIDE")"
assert_eq "$n" "0" "S2c: ordinary prompt => keyword pre-filter bails, 0 events, no model"

# 2d: stubbed classifier = maybe => NO event (only 'yes' captures).
new_scenario
export SDLC_CLASSIFIER_STUB="maybe"
run_correction_hook "why did you do that instead of the other thing" ""
n="$(jlines "$SDLC_JOURNAL_OVERRIDE")"
assert_eq "$n" "0" "S2d: stub=maybe => 0 events (maybe handled by drain-time gate, not hook)"
echo

# ===========================================================================
# SCENARIO 3 — toggle hard-gate. With .sdlc-lessons-disabled present, BOTH
# hooks must write nothing and exit 0.
# ===========================================================================
echo "--- SCENARIO 3: toggle hard-gate (.sdlc-lessons-disabled) ---"

# 3a: SubagentStop disabled — even with the REAL well-formed transcript.
new_scenario
touch "$SDLC_LESSONS_FLAG_OVERRIDE"   # present => disabled
run_subagent_hook "$REAL_FIXTURE" "sdlc-plan-challenger"
rc=$?
assert_eq "$rc" "0" "S3a: SubagentStop exits 0 when disabled"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S3a: SubagentStop writes nothing when disabled"

# 3b: UserPromptSubmit disabled — even with stub=yes and a correction prompt.
new_scenario
touch "$SDLC_LESSONS_FLAG_OVERRIDE"
export SDLC_CLASSIFIER_STUB="yes"
run_correction_hook "you should always use git -C instead" ""
rc=$?
assert_eq "$rc" "0" "S3b: UserPromptSubmit exits 0 when disabled"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S3b: UserPromptSubmit writes nothing when disabled (stub=yes ignored)"
echo

# ===========================================================================
# SCENARIO 4 — schema / robustness.
# ===========================================================================
echo "--- SCENARIO 4: schema / robustness ---"

# Helper: build a synthetic transcript whose LAST assistant entry carries $text.
make_transcript() {
  local out="$1" text="$2"
  : >"$out"
  jq -cn '{type:"user", message:{content:[{type:"text", text:"do the work"}]}}' >>"$out"
  jq -cn '{type:"assistant", message:{content:[{type:"text", text:"intermediate, no lessons"}]}}' >>"$out"
  jq -cn --arg t "$text" \
    '{type:"assistant", message:{content:[{type:"text", text:"## Summary\nDone.\n\n"},{type:"text", text:$t}]}}' >>"$out"
  jq -cn '{type:"user", message:{content:[{type:"text", text:"thanks"}]}}' >>"$out"  # trailing non-assistant
}

# 4a: missing ## Lessons => 0 events, exit 0.
new_scenario
make_transcript "$SCN_DIR/t.jsonl" "## Summary
Did the work, nothing to report."
run_subagent_hook "$SCN_DIR/t.jsonl" "sdlc-developer"
rc=$?
assert_eq "$rc" "0" "S4a: no ## Lessons => exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S4a: no ## Lessons => 0 events"

# 4b: malformed block (missing Suggested target) => 0 events, warning logged, exit 0.
new_scenario
make_transcript "$SCN_DIR/t.jsonl" "## Lessons

### Lesson
Trigger: something happened.
Generalizable rule: do the thing.
Suggested fix type: instruction-edit"
run_subagent_hook "$SCN_DIR/t.jsonl" "sdlc-developer"
rc=$?
assert_eq "$rc" "0" "S4b: malformed block => exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S4b: malformed block => 0 events"
wlog="$SCN_DIR/sdlc-events.warnings.log"
if [ -f "$wlog" ] && grep -q 'malformed' "$wlog"; then
  ok "S4b: malformed block => warning logged (not silent)"
else
  fail "S4b: expected a 'malformed' warning in $wlog"
fi

# 4c: multiple ### Lesson blocks (2 well-formed + 1 malformed) => exactly 2 events.
new_scenario
make_transcript "$SCN_DIR/t.jsonl" "## Lessons

### Lesson
Trigger: first friction.
Generalizable rule: first rule.
Suggested fix type: hook
Suggested target: plugins/ai-sdlc/hooks/a.sh

### Lesson
Trigger: malformed, no target.
Generalizable rule: a rule.
Suggested fix type: script

### Lesson
Trigger: third friction.
Generalizable rule: third rule.
Suggested fix type: skill
Suggested target: plugins/ai-sdlc/skills/y"
run_subagent_hook "$SCN_DIR/t.jsonl" "sdlc-architect"
rc=$?
assert_eq "$rc" "0" "S4c: multi-block => exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "2" "S4c: 2 well-formed + 1 malformed => exactly 2 events"

# 4d: corrupt / malformed transcript JSONL => 0 events, exit 0 (never crash).
new_scenario
printf '%s\n' 'this is not json at all {{{' >"$SCN_DIR/t.jsonl"
printf '%s\n' '{"type":"assistant"' >>"$SCN_DIR/t.jsonl"   # truncated JSON
run_subagent_hook "$SCN_DIR/t.jsonl" "sdlc-developer"
rc=$?
assert_eq "$rc" "0" "S4d: corrupt transcript => exit 0 (no crash)"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S4d: corrupt transcript => 0 events"

# 4e: missing transcript file => 0 events, exit 0.
new_scenario
run_subagent_hook "$SCN_DIR/does-not-exist.jsonl" "sdlc-developer"
rc=$?
assert_eq "$rc" "0" "S4e: missing transcript => exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S4e: missing transcript => 0 events"

# 4f: empty prompt to the correction hook => 0 events, exit 0.
new_scenario
run_correction_hook "" ""
rc=$?
assert_eq "$rc" "0" "S4f: empty prompt => exit 0"
assert_eq "$(jlines "$SDLC_JOURNAL_OVERRIDE")" "0" "S4f: empty prompt => 0 events"
echo

# ===========================================================================
# Real-journal protection assertion: confirm we never wrote to the real path.
# ===========================================================================
REAL_JOURNAL="$HOME/.claude/projects/-Users-maorb-git-dev/memory/sdlc-events.jsonl"
if [ -f "$REAL_JOURNAL" ]; then
  ok "real journal exists and was untouched (all writes used SDLC_JOURNAL_OVERRIDE temp paths)"
else
  ok "real journal not present; smoke run used only temp journals"
fi

echo
echo "================================================================"
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
echo "================================================================"
[ "$FAIL" -eq 0 ]
