# Design system

All values below are already in `assets/template.html`. This file explains them, so new components
stay consistent.

## Colour tokens

```css
:root{
  --bg:#050b17; --bg2:#0a1628; --panel:rgba(16,36,62,.55); --line:rgba(120,190,255,.16);
  --cyan:#4fd6ea; --gold:#f3c46b; --violet:#8c6cff; --blue:#3a7bff; --red:#ff4d5e; --green:#3ee08f;
  --text:#eaf1fa; --muted:#93a6bf; --dim:#5d6f88;
}
```

| Token | Use |
|---|---|
| `--bg` / `--bg2` | Page background / opaque fills inside cards (step circles, icon tiles) |
| `--line` | Every hairline border: cards, tags, buttons, image frames |
| `--cyan` | Primary accent: kickers, h3, links, the active dot, lines and pulses |
| `--gold` | Big numbers, "attention", pending or placeholder states, thank-you notes |
| `--violet` | Second stop in cyan gradients; secondary entity colour |
| `--green` / `--red` | Positive deltas and "solution" / risks, "problem", alerts |
| `--text` / `--muted` / `--dim` | Headlines / body and captions / footers and hints |

Body copy is `#c9d6e6`, a little softer than `--text`.

### Entity accents (`--c`)

When a slide shows several parallel things (teams, people, products), each gets an accent colour set
inline (`style="--c:#b6a3ff"`). A component uses it for:
- a 4–5px top border, or a dot inside a tag;
- a glow: `box-shadow:0 30px 80px -40px var(--c)`;
- a tinted border: `color-mix(in srgb,var(--c) 40%,transparent)`.

A palette that works on the navy background:
`#ff6b7a #ffd166 #3ee08f #4fd6ea #5aa8ff #b6a3ff #f39c6b #7fe0c8 #f3c46b #ff6ec7 #a58cff`.
Keep the same colour for the same entity on every slide.

### Gradients

- Accent gradient: `linear-gradient(90deg,var(--cyan),var(--violet))`, used for bars, the progress
  bar, numbers and lines.
- Moving hero text, `.grad`: white → `#9fe9ff` → `#a58cff` → white, sliding over 6s. Use it on one or
  two words per slide at most.
- Outlined numbers: `-webkit-text-stroke:1.5px var(--cyan);color:transparent`, for agenda indexes.

## Typography

```css
--font:"Inter","SF Pro Display",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
```

| Role | Size / weight | Notes |
|---|---|---|
| Hero (title slides) | 150–210 / 800 | letter-spacing −.045em |
| h1 | 120 / 800 | −.03em, line-height 1 |
| h2 (slide title) | 60 / 750 | −.02em, line-height 1.08 |
| h3 / subtitle | 30 / 700 | cyan |
| Card title | 26–34 / 700–750 | |
| Body `p` | 25 / 400 | line-height 1.5; 20–22 inside dense cards |
| Kicker | 18–22 / 600 | uppercase, letter-spacing .14em, cyan, sits above h2 |
| Presenter | 21 / 500 | cyan, with a short gradient dash before it |
| Captions, basis lines | 17–19 | `--muted` |
| Big numbers | 54–72 / 800 | gold or gradient, `font-variant-numeric:tabular-nums` |

Never go below 17px: it has to read on a projector.

## Layout

- Stage 1600×900. Slide padding `90px 110px`; tight slides can go to `56px 110px`.
- Slide heading block `.head`: a kicker and h2 (and optional presenter), gap 18, `margin-bottom:54px`.
- Grid gaps: 22–36px between cards; 70–90px between large person or photo blocks.
- Up to four cards per row; for more, use two rows or a different visual.
- Balance vertically. If the content is short, move it down (a larger `margin-top`) rather than leaving
  the bottom half empty.
- Keep content above y≈820, clear of the controls. Dots live at x≈26, so nothing goes in the left 70px.
- Captions that sit under a scene: `position:absolute;left:0;right:0;bottom:118px;text-align:center;font-size:36px`.

## Surfaces

**Card**
```css
.card{background:linear-gradient(160deg,rgba(24,52,88,.62),rgba(10,22,40,.62));border:1px solid var(--line);
  border-radius:22px;backdrop-filter:blur(10px);position:relative;overflow:hidden;
  box-shadow:0 20px 60px -20px rgba(0,0,0,.6),inset 0 1px 0 rgba(255,255,255,.05)}
```
A light sweep crosses each card once when the slide enters (`.card::after`, in the template).

**Tag / pill**: a 999px radius, the hairline border, 18px muted text and a pulsing 8px dot (gold by
default; set it to `var(--c)` for entity tags). Use it for status ("Draft", "Next step", "Today").

**Icon tile**: a 56–100px rounded square (radius 15–26), with a translucent accent fill or the dark card
gradient, a tinted border and a glow. Line icons are 24×24 viewBox, stroke 1.8–2, round caps.

**Image frame**: radius 18–24, the hairline border, a coloured or black drop shadow. Photos of people:
`object-fit:cover;object-position:center 15%`, with a coloured top border.

**Full-bleed image**: `.bleed` covers the slide. Put a dark gradient over the text side
(`linear-gradient(90deg,rgba(5,11,23,.92) 0%,rgba(5,11,23,.55) 45%,transparent 75%)`), and keep the
text in the darkened half.

**Dashed card**: `border:1px dashed rgba(243,196,107,.5)`, for "next", "future" or "missing" items.

## Media

- **Logos, not names.** When a slide names tools or products, show the brand logo in its brand colour,
  using Simple Icons-style single-path SVGs inlined in the page. Where there's no brand, use a line icon
  in the same style (24×24, stroke 1.8, round caps).
- **Characters.** A simple rounded body and round head, soft shading, dot eyes that blink, a mouth for
  the mood (smile, "o", worry) and a gentle bob, coloured with the entity's accent. Managers get a gold
  tie, builders a laptop. The template's `person()` draws them.
- **Images.** Full-bleed art sits with the text side darkened; photos and screenshots sit in rounded
  frames with a hairline border and a shadow or glow.
- **Video.** A large rounded black frame with native controls, a pulsing round play button and the
  first frame as a poster.
- **Single file.** Everything is inlined: images as data URIs, video as an embedded block turned into a
  blob URL. There are no external URLs, CDNs or web fonts, and the file opens offline by double-click.

## Chrome (do not restyle per deck)

- Dots: 10px circles at 28% white. The active dot stretches to 30px tall in cyan with a glow, and each
  dot shows a label on hover.
- Progress bar: 3px at the top, accent gradient.
- Bottom bar: previous and next buttons, an `NN / NN` counter and a full-screen button, at 25% opacity
  until the mouse moves.
- Hint at the top right: "← → navigate · F fullscreen · O overview", fading out after 5s.
