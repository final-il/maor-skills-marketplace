#!/usr/bin/env bash
# Integration tests for capture-user-correction.sh (CSI-639).
#
# Fully hermetic: SDLC_CLASSIFIER_STUB bypasses the real Haiku call so no test
# ever touches the network, and SDLC_JOURNAL_OVERRIDE / SDLC_LESSONS_FLAG_OVERRIDE
# redirect all writes into a temp dir — the real journal at ~/.claude/... is
# never touched.
#
# Run:  bash plugins/ai-sdlc/hooks/tests/test_capture_user_correction.sh
# Exit: 0 = all pass, 1 = any failure.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOKS_DIR/capture-user-correction.sh"

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

# Build a transcript JSONL whose last assistant entry carries a tool_use + text
# (a realistic "last action" the classifier could see).
make_transcript() {
  local out="$1"
  : >"$out"
  jq -cn '{type:"user", message:{content:[{type:"text", text:"build the parser"}]}}' >>"$out"
  jq -cn '{type:"assistant", message:{content:[{type:"text", text:"I ran the build"},{type:"tool_use", name:"Bash", input:{command:"cd src && make"}}]}}' >>"$out"
}

# Run the hook with a given prompt, transcript path, and classifier stub.
# $1 = prompt, $2 = transcript path (may be empty/nonexistent), $3 = stub verdict
run_hook() {
  local prompt="$1" tp="$2" stub="$3"
  jq -cn --arg p "$prompt" --arg tp "$tp" \
    '{session_id:"s1", transcript_path:$tp, cwd:".", hook_event_name:"UserPromptSubmit", prompt:$p}' \
    | SDLC_CLASSIFIER_STUB="$stub" bash "$HOOK"
}

# Run the hook WITHOUT a classifier stub (to exercise the real-call fail-safe
# branch). Both ANTHROPIC_API_KEY (direct) and ANTHROPIC_AUTH_TOKEN (proxy) are
# forced empty so the no-auth fail-safe fires and it never hits the network.
run_hook_no_stub() {
  local prompt="$1" tp="$2"
  jq -cn --arg p "$prompt" --arg tp "$tp" \
    '{session_id:"s1", transcript_path:$tp, cwd:".", hook_event_name:"UserPromptSubmit", prompt:$p}' \
    | env -u SDLC_CLASSIFIER_STUB ANTHROPIC_API_KEY="" ANTHROPIC_AUTH_TOKEN="" bash "$HOOK"
}

journal_lines() {
  [ -f "$SDLC_JOURNAL_OVERRIDE" ] && wc -l <"$SDLC_JOURNAL_OVERRIDE" | tr -d ' ' || echo 0
}

# ===========================================================================
# Test 1: keyword MISS → no event AND no LLM call. We prove "no LLM call" by
# setting the stub to `yes` — if the hook had reached the classifier it would
# write an event. A keyword-free prompt must short-circuit before that.
# ===========================================================================
T1="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T1/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T1/.disabled"
make_transcript "$T1/t.jsonl"
run_hook "Please add a new endpoint that returns the list of users." "$T1/t.jsonl" "yes"
assert_eq "$(journal_lines)" "0" "keyword miss → 0 events (LLM not consulted despite stub=yes)"
rm -rf "$T1"

# ===========================================================================
# Test 2: keyword HIT + stub `yes` → exactly one correct raw user-correction event.
# ===========================================================================
T2="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T2/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T2/.disabled"
make_transcript "$T2/t.jsonl"
run_hook "You forgot to commit. Use git -C instead of cd." "$T2/t.jsonl" "yes"
assert_eq "$(journal_lines)" "1" "keyword hit + stub=yes → exactly 1 event"
if [ "$(journal_lines)" = "1" ]; then
  evt="$(tail -1 "$SDLC_JOURNAL_OVERRIDE")"
  assert_eq "$(printf '%s' "$evt" | jq -r .status)" "raw" "status == raw"
  assert_eq "$(printf '%s' "$evt" | jq -r .source)" "user-correction" "source == user-correction"
  assert_eq "$(printf '%s' "$evt" | jq -r '.agent')" "null" "agent == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.epic')" "null" "epic == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.story')" "null" "story == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.phase')" "null" "phase == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.extractor_run')" "null" "extractor_run == null"
  assert_eq "$(printf '%s' "$evt" | jq -r '.applied_commit')" "null" "applied_commit == null"
  if printf '%s' "$evt" | jq -r .id | grep -qE '^evt_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9a-f]{6}$'; then
    ok "id matches evt_<date>_<time>_<6hex>"
  else fail "id format ($(printf '%s' "$evt" | jq -r .id))"; fi
  if printf '%s' "$evt" | jq -r .trigger_summary | grep -q 'You forgot to commit'; then
    ok "trigger_summary captured from prompt"
  else fail "trigger_summary"; fi
  ev="$(printf '%s' "$evt" | jq -r .evidence)"
  if printf '%s' "$ev" | grep -q 'You forgot to commit' \
     && printf '%s' "$ev" | grep -q 'LAST ACTIONS' \
     && printf '%s' "$ev" | grep -q 'tool_use:Bash'; then
    ok "evidence = verbatim prompt + reconstructed last actions"
  else fail "evidence content ($ev)"; fi
  # Schema parity check: exact key set matches CSI-638's raw event.
  keys="$(printf '%s' "$evt" | jq -cS 'keys')"
  assert_eq "$keys" '["agent","applied_commit","epic","evidence","extractor_run","id","phase","source","status","story","trigger_summary","ts"]' "event key set matches schema"
fi
rm -rf "$T2"

# ===========================================================================
# Test 3: keyword HIT + stub `no` → no event.
# ===========================================================================
T3="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T3/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T3/.disabled"
make_transcript "$T3/t.jsonl"
# Contains "no" (keyword) but is a genuine new instruction, not a correction.
run_hook "Add a no-op fallback when the cache is cold." "$T3/t.jsonl" "no"
assert_eq "$(journal_lines)" "0" "keyword hit + stub=no → 0 events"
rm -rf "$T3"

# ===========================================================================
# Test 4: keyword HIT + stub `maybe` → no event (out-of-band hook is yes-only).
# ===========================================================================
T4="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T4/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T4/.disabled"
make_transcript "$T4/t.jsonl"
run_hook "Should that always run before the lint step?" "$T4/t.jsonl" "maybe"
assert_eq "$(journal_lines)" "0" "keyword hit + stub=maybe → 0 events"
rm -rf "$T4"

# ===========================================================================
# Test 5: missing ANTHROPIC_API_KEY (no stub) → fail-safe, no event, exit 0.
# ===========================================================================
T5="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T5/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T5/.disabled"
make_transcript "$T5/t.jsonl"
run_hook_no_stub "You forgot the SSL cert, why did you skip it?" "$T5/t.jsonl"
rc=$?
assert_eq "$rc" "0" "missing API key → exit 0 (fail-safe)"
assert_eq "$(journal_lines)" "0" "missing API key → 0 events (fail-safe no)"
rm -rf "$T5"

# ===========================================================================
# Test 6: toggle OFF (flag present) → no event even on a clear correction+yes.
# ===========================================================================
T6="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T6/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T6/.disabled"
touch "$SDLC_LESSONS_FLAG_OVERRIDE"   # present → disabled
make_transcript "$T6/t.jsonl"
run_hook "You forgot to commit, use git -C instead." "$T6/t.jsonl" "yes"
assert_eq "$(journal_lines)" "0" "toggle OFF → 0 events (no-op)"
rm -rf "$T6"

# ===========================================================================
# Test 7: keyword hit + yes but NO transcript file → still one event, evidence
# has the prompt but no LAST ACTIONS section. Exit 0.
# ===========================================================================
T7="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T7/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T7/.disabled"
run_hook "Stop using the deprecated API instead." "$T7/missing.jsonl" "yes"
rc=$?
assert_eq "$rc" "0" "missing transcript → exit 0"
assert_eq "$(journal_lines)" "1" "missing transcript + yes → still 1 event"
if [ "$(journal_lines)" = "1" ]; then
  ev="$(tail -1 "$SDLC_JOURNAL_OVERRIDE" | jq -r .evidence)"
  if printf '%s' "$ev" | grep -q 'Stop using the deprecated API' \
     && ! printf '%s' "$ev" | grep -q 'LAST ACTIONS'; then
    ok "no transcript → evidence has prompt, no LAST ACTIONS section"
  else fail "evidence without transcript ($ev)"; fi
fi
rm -rf "$T7"

# ===========================================================================
# Test 8: empty prompt → no event, exit 0.
# ===========================================================================
T8="$(mktemp -d)"
export SDLC_JOURNAL_OVERRIDE="$T8/journal.jsonl"
export SDLC_LESSONS_FLAG_OVERRIDE="$T8/.disabled"
run_hook "" "$T8/missing.jsonl" "yes"
assert_eq "$(journal_lines)" "0" "empty prompt → 0 events"
rm -rf "$T8"

# ===========================================================================
# Test 9 (hooks.json): UserPromptSubmit wired to the capture script, and the
# SubagentStop entry (CSI-638) is left intact.
# ===========================================================================
HOOKS_JSON="$HOOKS_DIR/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  ok "hooks.json exists"
  if jq -e '.hooks.UserPromptSubmit' "$HOOKS_JSON" >/dev/null 2>&1; then
    ok "hooks.json: UserPromptSubmit key present"
  else fail "hooks.json: UserPromptSubmit key missing"; fi
  if jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS_JSON" 2>/dev/null | grep -q 'capture-user-correction'; then
    ok "hooks.json: UserPromptSubmit command references capture-user-correction"
  else fail "hooks.json: UserPromptSubmit command wrong"; fi
  if jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOOKS_JSON" 2>/dev/null | grep -q 'capture-subagent-lessons'; then
    ok "hooks.json: SubagentStop (CSI-638) left intact"
  else fail "hooks.json: SubagentStop entry disturbed"; fi
else
  fail "hooks.json not found at $HOOKS_JSON"
fi

# ===========================================================================
echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
