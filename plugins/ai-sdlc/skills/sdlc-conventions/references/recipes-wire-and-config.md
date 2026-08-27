# Recipe: Wire-contract, Smoke-path & Live-process/Config gates (load on demand)

**When to load this file:** the tester loads it when a story has a `## Wire Contracts` or
`## Smoke Path` section, or the diff touches an HTTP/SSE/WebSocket endpoint, browser code,
an external-service integration, or a config/infra artifact. The QA reviewer loads it when
verifying those same gates. If none of those apply (a genuinely backend-internal story with
no wire/smoke/config surface), you do NOT need this file — the inline mandates in the role
file are sufficient.

**These are the execution procedures.** The *mandates and triggers* stay in the role files
(`sdlc-tester.md`, `sdlc-qa-reviewer.md`) so they are always in context; this file holds the
*how*. Nothing here is optional when its trigger fires — it is moved for context economy, not
downgraded in authority.

---

## 1. Wire-contract tests (procedure)

For every wire contract a story produces or consumes, write at least one **end-to-end contract
test** that runs the real producer and the real consumer in the same test process and asserts
the full round-trip on real bytes:

- **HTTP endpoint:** spawn the real app with a real client (e.g. `httpx.ASGITransport`) and
  assert the response shape against the schema location named in `## Wire Contracts`.
- **SSE:** drive bytes from the **real** producer (`event_to_sse` or equivalent) into the
  **real** frontend parser. Use the real wire separator (`\r\n\r\n`) — do not hand-construct
  frames the parser would obviously accept.
- **JSON-RPC / WebSocket / IPC:** feed the real producer's serialized output into the real
  consumer's deserializer; assert the dispatched event/object equals the expected shape.
- **File formats:** write with the real producer, read with the real consumer; never test one
  half against a hand-rolled fixture.

If the story is the **producer**: call it, capture the bytes/payload, feed those bytes through
whatever consumer code exists in the repo (import the frontend parser into a node test, or the
consumer module into a Python test). If the consumer runs in a different runtime (browser-only
TS), produce a fixture file from the real producer at the schema location's directory; the
consumer-side story's tester loads and parses it.

If the story is the **consumer**: import the producer (or the canonical schema's reference
implementation) to generate input bytes for your parser test. Do NOT hand-author wire-byte
fixtures.

The acceptance criterion **"matches the wire contract in `<schema location>`"** is implicit on
every wire-bearing story even if the description omits it. Treat it as AC0.

**Banned patterns** (these are why CSI-529 / CSI-530 / CSI-531 slipped through):
- ❌ Test feeds a fixture into the parser and asserts it parses. You authored the fixture — the
  parser will obviously accept it. That tests the parser against itself, not the producer.
- ❌ Test normalizes wire bytes (e.g. `text.replace("\r\n", "\n")`) before parsing. The bug you
  are trying to catch lives in the bytes you just normalized away.
- ❌ Frontend test uses a different event-name set than the backend emits (`event: token` mock
  when the backend emits `event: text`).
- ❌ Backend test asserts the SSE comment looks right but never feeds it to the frontend parser.

## 2. Smoke-path artifact (procedure)

The tech spec's `## Smoke Path` names a concrete command, a success signal, and a failure signal.
The smoke path is **not unit-testable** — it is the proof the story participated in its epic-level
CUJ. Run it against a **real running system** and save an observable artifact.

**Run the smoke command literally:**
- `curl` against a running backend → start the backend (Gate 1 below), run the curl, capture the
  response body + HTTP code to `tests/artifacts/{STORY-KEY}/smoke.txt` (or `.json`).
- Playwright spec → run against a running dev server; save the screenshot to
  `tests/artifacts/{STORY-KEY}/smoke.png` (add `await page.screenshot({path: ..., fullPage: true})`
  if the spec doesn't already).
- CLI command → run the real binary (e.g. `uv run jiralyzer query ...`); save stdout+stderr.
- Browser flow without Playwright in-repo → install Playwright, write a one-shot spec, screenshot it.

**Verify the success signal is present in the artifact** (grep/parse/inspect). Missing signal =
smoke failed → file a Bug, do not approve. **Visually look at any screenshot** — "0 console errors"
is necessary but not sufficient; a blank/wrong page is a fail. Commit the artifact:
`git add tests/artifacts/{STORY-KEY}/`.

## 3. Live-process gates 1–4 (procedure)

Run the applicable gates **green** before posting `## Test Results`.

**Gate 1 — Backend live-process (any FastAPI/HTTP/SSE change):** start the real backend
(`nohup ./test.sh python -m jiralyzer_web > /tmp/test-backend.log 2>&1 &`), wait for
`Application startup complete.`. For each touched endpoint, `curl` with a representative payload
(SSE: stream ≥5 events). Assert wire shape matches `## Wire Contracts` (`jq` for JSON). Any
`ERROR`/`Traceback` in the log is a failure even on a 200. Kill cleanly.

**Gate 2 — Browser smoke (any user-visible frontend change):** run the repo's `test:e2e`
(Playwright/Cypress). If none is installed, install Playwright and add a spec that loads the
preview URL, exercises the story's flow, and asserts zero `pageerror`, zero `console.error`, no
error-boundary overlay. Catches React-runtime errors vitest never sees.

**Gate 3 — External-service (any credentials/base-URL/model-name/SDK-config change):** make
exactly one real call per external service (LiteLLM/Anthropic, Jira, S3, …). Capture code + first
200 chars under a `#### External-Service Probe` heading. A 4xx/5xx IS a failure — file a Bug, do
not paper over with try/except.

**Gate 4 — Config & Infra (any deploy/config/infra artifact, or an env/config key that differs
per environment):** the concrete invariants come from the tech spec's `## Config & Infra Contract`.
(a) Write deterministic config-assertion tests that parse the real artifacts and assert:
target-mode pinning, required-key presence, secrets-referenced-not-hardcoded, network/proxy/gateway
invariants, service-wiring consistency — whichever apply. (b) Run the smoke/live gates in the
**deploy-target runtime mode** (from `## Config & Infra Contract → TARGET RUNTIME MODE`), routed
through the same front door/gateway the target uses. Environment-gated bugs (auth/authz rejections,
proxy/buffering failures, subpath mismatches) are invisible in the permissive dev mode.
*Web example (jiralyzer): parse `deploy/env/*.env` + compose `environment:` and assert `AUTH_MODE`
is `users` not `open`; parse `nginx.conf.template` for `location` ordering + `proxy_buffering`/
`proxy_temp` + upstream resolution. Substitute your stack's equivalents.*

**Chat-agent gate (chat router / agent loop / tools / persistence):** beyond a single-turn probe,
run a **second-turn replay** — send turn 1, persist, then a turn 2 that exercises the persisted
`tool_use` blocks (the "tool_use.input must be a dict" class only surfaces on replay). For any
persistence change, load every fixture under `tests/fixtures/conversations/` (create the dir + one
fixture if none) through the real loader and assert no exception; the fixture must reflect the
on-disk Anthropic shape `{role, content:[...]}`, not the frontend `ChatMessage` shape.

**Recorded fixtures (frontend tests consuming backend responses):** if `tools/capture-fixtures.sh`
exists, re-run it when your story changes any backend response shape and commit the regenerated
fixtures. Frontend component/hook tests that mock `/api/*` MUST load the recorded JSON from
`web/frontend/tests/fixtures/api/` — hand-rolled mock dicts are a banned pattern the QA reviewer
rejects.

## 4. QA verification of the above (procedure)

The QA reviewer confirms the gates were really run and aren't fakes:
- **Wire (c.1):** open the test file; confirm ≥1 test feeds real producer bytes into the real
  consumer parser. Reject any banned pattern (fixture-against-parser, byte-normalization before
  parse, event-name mismatch, wrong schema). No end-to-end test on a `## Wire Contracts` story = Bug.
- **Smoke (c.1.5):** `ls tests/artifacts/{STORY-KEY}/`; read the artifact; confirm the success
  signal from `## Smoke Path`; for `.png`, open it with the Read tool and **look**. A referenced-but-
  missing artifact is fabricated → Bug. Never skipped, even in Fast Mode.
- **Live gates (c.2):** the `#### Live Gates Run` section must name a real command + outcome per
  applicable gate; generic "all green" fails. Frontend → Playwright spec run/added with the
  no-console-error assertion. Chat/persistence → second-turn replay present.
- **Config (c.6):** confirm Gate-4 config-assertion tests exist and assert the `## Config & Infra
  Contract` invariants, and that the smoke/live gate ran in the deploy-target mode — reject
  "tested in the dev-permissive mode" for a stricter target.
