#!/usr/bin/env node
// sdlc-compose — build-time composition + drift check for ai-sdlc agent files.
//
// WHY: 13 agent role files each ship a byte-identical shared block (the `## Lessons`
// self-learning contract). Duplicated prose drifts — that drift produced ~9 of the 13
// consistency bugs fixed in this repo. This tool keeps ONE canonical copy per shared
// fragment and syncs it into the self-contained agent files, so the deterministic
// runtime path (pointer -> complete role file -> action) is UNCHANGED while there is a
// single editable source. It does NOT touch role-specific content (MCP tool selections,
// fast-mode artifacts/verdicts, gates, artifact contracts) — those stay per-agent.
//
// Fragments are TAIL-anchored: a fragment owns the region from an anchor line to EOF.
// (The only cleanly-shared, byte-identical block today — `## Lessons` — is always the
// file tail, so no inline markers are needed. Non-tail blocks have per-agent variation
// and are deliberately NOT managed here.)
//
// Usage:
//   node build/sdlc-compose.mjs check    # exit 1 if any managed region drifted from its fragment
//   node build/sdlc-compose.mjs write    # rewrite managed regions from the fragments (idempotent)

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const AGENTS_DIR = join(ROOT, 'agents');
const FRAG_DIR = join(ROOT, 'build', 'fragments');

// Managed fragments. Each owns the tail of every agent file whose current tail begins
// with `anchor`. Agents without the anchor are skipped (e.g. curator / lesson-extractor /
// documenter legitimately omit the Lessons block).
const FRAGMENTS = [
  { name: 'lessons', file: 'lessons.md', anchor: '## Lessons (optional' },
];

function agentFiles() {
  return readdirSync(AGENTS_DIR)
    .filter((f) => f.endsWith('.md'))
    .map((f) => join(AGENTS_DIR, f));
}

// Returns { head, tail } split at the first line beginning with anchor, or null if absent.
function splitAtAnchor(text, anchor) {
  const lines = text.split('\n');
  const idx = lines.findIndex((l) => l.startsWith(anchor));
  if (idx === -1) return null;
  return { head: lines.slice(0, idx).join('\n'), tail: lines.slice(idx).join('\n') };
}

function run(mode) {
  let drift = 0;
  let wrote = 0;
  let managed = 0;
  for (const frag of FRAGMENTS) {
    const canonical = readFileSync(join(FRAG_DIR, frag.file), 'utf8');
    for (const path of agentFiles()) {
      const text = readFileSync(path, 'utf8');
      const split = splitAtAnchor(text, frag.anchor);
      if (!split) continue; // fragment not present in this agent — by design
      managed++;
      const current = split.tail;
      if (current === canonical) continue;
      if (mode === 'check') {
        drift++;
        console.error(`DRIFT: ${path.replace(ROOT + '/', '')} — '${frag.name}' region diverges from build/fragments/${frag.file}`);
      } else if (mode === 'write') {
        // head + a single blank-line separator is already inside head/tail boundary,
        // so rejoin head + '\n' + canonical to preserve the exact original layout.
        writeFileSync(path, split.head + '\n' + canonical);
        wrote++;
      }
    }
  }
  if (mode === 'check') {
    if (drift) {
      console.error(`\n${drift} drifted region(s) across ${managed} managed region(s). Run: node build/sdlc-compose.mjs write`);
      process.exit(1);
    }
    console.log(`OK — ${managed} managed region(s) match their fragments (${FRAGMENTS.length} fragment type(s)).`);
  } else {
    console.log(`Wrote ${wrote} region(s); ${managed} managed region(s) total.`);
  }
}

const mode = process.argv[2];
if (mode !== 'check' && mode !== 'write') {
  console.error('Usage: node build/sdlc-compose.mjs <check|write>');
  process.exit(2);
}
run(mode);
