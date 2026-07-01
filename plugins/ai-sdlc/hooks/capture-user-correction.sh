#!/usr/bin/env bash
# AI-SDLC self-learning — UserPromptSubmit correction-capture hook (CSI-639).
#
# Removes the main orchestrator model from the capture decision. On every user
# prompt this hook:
#   1. KEYWORD PRE-FILTER — a cheap regex over the raw prompt for correction
#      signals (instead, you forgot, why did you, should have, always, never,
#      don't, stop, no, actually, not what, ...). NO keyword hit → exit 0
#      immediately, with NO LLM call (so the vast majority of prompts are free).
#   2. HAIKU CLASSIFIER — on a keyword hit, call Haiku out-of-band, passing the
#      user prompt + the last 1-2 actions reconstructed from transcript_path, to
#      classify the correction intent as exactly `yes` | `maybe` | `no`.
#   3. JOURNAL APPEND — on `yes`, append one `source:"user-correction"`,
#      `status:"raw"` event to the same journal + via the same lib as CSI-638.
#      `maybe` / `no` → no event.
#
# Best-effort by contract: any error (toggle off, no API key, classifier error
# or timeout, no transcript, IO failure, missing jq) results in `exit 0` and at
# most a sidecar-log warning. This hook MUST NEVER break the pipeline. The
# classifier fail-safes to `no` (no event) on any failure.
#
# Test seams (relied on by CSI-641):
#   SDLC_CLASSIFIER_STUB   — if set, bypasses the real Haiku call and is used
#                            verbatim as the classifier verdict (yes|maybe|no).
#                            Lets smoke tests stay hermetic / never hit network.
#   SDLC_JOURNAL_OVERRIDE  — (from lib) redirect the journal to a temp file.
#   SDLC_LESSONS_FLAG_OVERRIDE — (from lib) point the disable flag elsewhere.
#
# NOT `set -e` — a hard abort would defeat the fail-safe guarantee.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/journal-append.sh
. "$SCRIPT_DIR/lib/journal-append.sh" || exit 0

# Zscaler corporate CA bundle — required for any HTTPS to the Anthropic API
# (direct or via a LiteLLM/proxy endpoint).
SSL_CERT_FILE_PATH="/Users/maorb/.config/uv/ca-bundle.pem"

# Auth + endpoint resolution. This machine (and any proxied setup) routes
# Claude traffic through a LiteLLM/headroom proxy that authenticates with a
# Bearer token, NOT the direct-API `x-api-key`. Resolve, in priority order:
#   - key:  ANTHROPIC_API_KEY (direct) → ANTHROPIC_AUTH_TOKEN (proxy/LiteLLM)
#   - base: ANTHROPIC_BASE_URL if set  → else the direct api.anthropic.com
#   - model: ANTHROPIC_DEFAULT_HAIKU_MODEL (proxy alias) → direct default
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-${ANTHROPIC_AUTH_TOKEN:-}}"
ANTHROPIC_BASE="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
ANTHROPIC_BASE="${ANTHROPIC_BASE%/}"   # strip any trailing slash
HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-claude-haiku-4-5}"

# ---- read stdin payload ----------------------------------------------------
STDIN_JSON="$(cat 2>/dev/null || true)"

# Toggle gate: if disabled, no-op immediately.
if ! lessons_enabled; then
  exit 0
fi

# jq is required for stdin parsing, transcript parsing, and JSON emit.
if ! command -v jq >/dev/null 2>&1; then
  warn "capture-user-correction: jq not found on PATH; skipping capture"
  exit 0
fi

# ---- extract stdin fields --------------------------------------------------
field() {
  printf '%s' "$STDIN_JSON" | jq -r "(.$1 // \"\")" 2>/dev/null || printf ''
}
PROMPT="$(field prompt)"
TRANSCRIPT_PATH="$(field transcript_path)"

if [ -z "$PROMPT" ]; then
  # Nothing to classify.
  exit 0
fi

# ---- (1) keyword pre-filter ------------------------------------------------
# Case-insensitive ERE over correction signals. If NO signal matches, bail
# BEFORE any LLM call. `no\b` uses a word boundary so it doesn't match "note".
CORRECTION_RE='instead|you forgot|why did you|why didn'\''t you|should have|should'\''ve|shouldn'\''t have|always|never|don'\''t|do not|stop|no\b|actually|not what|that'\''s wrong|that is wrong|you were supposed|from now on|use .* not'

if ! printf '%s' "$PROMPT" | grep -qiE "$CORRECTION_RE"; then
  # Common case: ordinary prompt, no correction signal. Free exit, no LLM.
  exit 0
fi

# ---- reconstruct last 1-2 actions from transcript --------------------------
# Take the LAST assistant entry and concatenate its text content blocks. This
# is the "what I just did" context the classifier needs to tell a correction
# apart from a fresh instruction. Best-effort; empty string if unavailable.
LAST_ACTIONS=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_ACTIONS="$(
    jq -rs '
      [ .[] | select(.type == "assistant") ] as $a
      | if ($a | length) == 0 then ""
        else ($a[-1].message.content // [])
             | map(if .type == "text" then .text
                   elif .type == "tool_use" then ("[tool_use:" + (.name // "?") + "]")
                   else empty end)
             | join("\n")
        end
    ' "$TRANSCRIPT_PATH" 2>/dev/null || true
  )"
  # Bound the context so we never ship a giant transcript to the classifier.
  LAST_ACTIONS="$(printf '%s' "$LAST_ACTIONS" | head -c 2000)"
fi

# ---- (2) classify correction intent: yes | maybe | no ----------------------
# Stub seam (CSI-641): bypass network entirely when SDLC_CLASSIFIER_STUB is set.
classify_intent() {
  if [ -n "${SDLC_CLASSIFIER_STUB:-}" ]; then
    printf '%s' "$SDLC_CLASSIFIER_STUB" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
    return 0
  fi

  # Fail-safe to `no` if no auth token — never block, never error out.
  if [ -z "${ANTHROPIC_KEY:-}" ]; then
    warn "capture-user-correction: no ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN; fail-safe classify=no"
    printf 'no'
    return 0
  fi

  local sys body verdict
  sys='You classify whether a user message is a CORRECTION of behavior the assistant or one of its sub-agents just took. Examples that qualify (yes): "use X instead", "you forgot Y", "why did you do Z", "from now on always W", "stop doing V", "that is not what I asked". Examples that do NOT qualify (no): clarifying questions, brand-new task instructions, status checks. If genuinely ambiguous, answer maybe. Respond with EXACTLY one lowercase word: yes, maybe, or no. No punctuation, no explanation.'

  # Assemble the request body. The user content (prompt + last actions) is
  # passed through the environment so jq escapes it correctly regardless of
  # quotes/newlines.
  body="$(
    SDLC_UP_PROMPT="$PROMPT" SDLC_UP_ACTIONS="$LAST_ACTIONS" \
    jq -cn --arg model "$HAIKU_MODEL" --arg sys "$sys" \
      '{model:$model, max_tokens:8, system:$sys,
        messages:[{role:"user",
          content:("USER MESSAGE:\n" + env.SDLC_UP_PROMPT
                   + "\n\nLAST 1-2 ASSISTANT/AGENT ACTIONS:\n"
                   + (if (env.SDLC_UP_ACTIONS|length)>0 then env.SDLC_UP_ACTIONS else "(none available)" end))}]}' 2>/dev/null
  )"
  if [ -z "$body" ]; then
    warn "capture-user-correction: failed to build classifier request; fail-safe=no"
    printf 'no'
    return 0
  fi

  # Out-of-band HTTPS call. 15s cap; any curl failure → fail-safe no.
  local resp
  resp="$(
    SSL_CERT_FILE="$SSL_CERT_FILE_PATH" \
    curl -sS --max-time 15 \
      -X POST "${ANTHROPIC_BASE}/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_KEY}" \
      -H "Authorization: Bearer ${ANTHROPIC_KEY}" \
      -H 'anthropic-version: 2023-06-01' \
      -H 'content-type: application/json' \
      --data "$body" 2>/dev/null || true
  )"
  if [ -z "$resp" ]; then
    warn "capture-user-correction: classifier call returned nothing (network/timeout); fail-safe=no"
    printf 'no'
    return 0
  fi

  verdict="$(
    printf '%s' "$resp" \
      | jq -r '(.content // []) | map(select(.type=="text") | .text) | join("")' 2>/dev/null \
      | tr '[:upper:]' '[:lower:]' | tr -d '[:space:][:punct:]'
  )"
  case "$verdict" in
    yes|maybe|no) printf '%s' "$verdict" ;;
    *)
      warn "capture-user-correction: unparseable classifier verdict ('$verdict'); fail-safe=no"
      printf 'no'
      ;;
  esac
}

VERDICT="$(classify_intent)"

# Only `yes` produces an event. `maybe` and `no` are intentional no-ops here:
# the live orchestrator handles the maybe-confirm path; this out-of-band hook
# captures only high-confidence corrections.
if [ "$VERDICT" != "yes" ]; then
  exit 0
fi

# ---- (3) append one raw user-correction event ------------------------------
# Schema matches CSI-638 byte-for-byte; only `source` differs.
trigger_summary="$(printf '%s' "$PROMPT" | head -c 200 | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
# Evidence = verbatim user message + the last actions that prompted it. jq
# escapes it on emit below, so keep it as a raw shell value here.
if [ -n "$LAST_ACTIONS" ]; then
  evidence="$(printf 'USER: %s\n\nLAST ACTIONS:\n%s' "$PROMPT" "$LAST_ACTIONS")"
else
  evidence="$(printf 'USER: %s' "$PROMPT")"
fi

evt_id="$(gen_event_id)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

line="$(
  jq -cn \
    --arg id "$evt_id" \
    --arg ts "$ts" \
    --arg trigger "$trigger_summary" \
    --arg evidence "$evidence" \
    '{
      id: $id,
      ts: $ts,
      epic: null,
      story: null,
      phase: null,
      agent: null,
      source: "user-correction",
      trigger_summary: $trigger,
      evidence: $evidence,
      extractor_run: null,
      status: "raw",
      applied_commit: null
    }' 2>/dev/null || true
)"

if [ -z "$line" ]; then
  warn "capture-user-correction: jq failed to serialize event"
  exit 0
fi

if append_event_json "$line"; then
  : # captured
else
  warn "capture-user-correction: journal append failed; event dropped"
fi

exit 0
