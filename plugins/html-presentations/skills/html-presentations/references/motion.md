# Motion

## The one rule

**The base CSS is the finished state.** Motion happens only under `.slide.active`, and keyframe
animations use `both` fill. Overview mode (O) switches off all motion and has to show complete slides,
so nothing may rest in a "hidden until animated" state.

## Character

- Easing: `--ease` (`cubic-bezier(.2,.8,.2,1)`) for every move, and `--spring`
  (`cubic-bezier(.34,1.56,.64,1)`) for pops. Use linear only for loops.
- Slide change: the new slide fades in from 60px to the right, at 98% scale with an 8px blur, over
  .7–.9s; the old one exits to the left. No other slide transitions.
- Entrances are staggered: title first, then siblings .1–.2s apart (`.rv` with `--d`). Elements rise
  26px, slide in 40px from the side, or scale from .85.
- A slide is fully arrived within ~1.5s. A later beat is a deliberate punchline ("But…"), not a slow
  build.
- Numbers count up (about 1.6s, ease-out). Bars grow, lines draw left to right, rings fill, and each
  card gets one light sweep as it enters.

## Life

Loops keep a slide alive, and they stay subtle and slow:
- float and bob: 2.6–5s, 5–10px, staggered so things never move in sync;
- characters blink every ~4s;
- a pulse travels along flow lines every ~3.6s;
- confetti and bubbles drift over 5–15s;
- hero gradient text shines over 6s;
- full-bleed images zoom slowly from 1.12 to 1 over 9s.

## Background

Fibre strands with travelling sparks, at very low alpha. **Its motion must be close to
imperceptible**: the user asked three times for it to be slower (4× and then 10×). The template has
the approved speed, so never make it faster. Turn it off when `prefers-reduced-motion` is set.

## Playful mode

When the user wants it playful: characters that act the scene (walk, turn, react, speech bubbles, a
"?" badge, a lightbulb), logos that fly in and land, items that pour into place, then a single big
caption per scene. Timing comes from CSS beats (`animation-delay`) under `.active`.

## Keys

Arrows, PageUp/PageDown, Home and End always navigate. On a slide with a video, Space, Enter and K play
or pause it, and leaving the slide pauses it.
