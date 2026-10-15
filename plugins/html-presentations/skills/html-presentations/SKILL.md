---
name: html-presentations
description: "Design system for animated single-file HTML presentations: dark glass look, staggered reveals, page dots, overview mode, embedded images and video, opens offline. Use whenever the user asks for an HTML presentation, an animated or 'slick' deck, a web version of a PowerPoint, or slides as a single shareable HTML file — even if they only say 'make it a presentation' or hand over a PPTX and ask to make it dynamic."
---

# HTML Presentations — design system

This skill defines how a presentation looks and moves. The content, the story, the slide list and the
layouts are yours to decide from the material.

Start every deck from `assets/template.html`: it is the reference implementation of these rules (stage,
tokens, cards, reveal, background, page dots, overview, video slide, characters).

## Design questions

Ask only what you can't infer, in one message:

1. **Look:** the default dark theme, or brand colours and a logo to work in?
2. **Motion:** calm and professional, or playful (characters acting scenes, logos flying)?
3. **Media:** video to include? It inflates the single file; confirm when the file passes ~20 MB.

## Rules

**Canvas.** A fixed 1600×900 stage, scaled to the window; design in stage pixels. Padding 90px top and
bottom, 110px left and right. Keep content above y≈820 and out of the left 70px (controls and dots).

**Look.** A deep navy background with a near-still fibre-optic canvas and a vignette. Content sits on
glass cards (a translucent gradient, a 1px hairline border, 22px radius, blur, a deep shadow). Cyan
leads; gold is for numbers and attention; violet pairs with cyan in gradients. Each parallel entity
(team, person, product) has its own accent colour, used consistently across all slides.

**Type.** System fonts only. h1 120 / h2 60 / h3 30 cyan / body 25 / an uppercase cyan kicker above the
slide title. Headlines are tight and heavy. Nothing below 17px.

**Motion.** The finished state is the base. Reveals are staggered and arrive within ~1.5s. Loops are
slow and subtle. The background barely moves.

**Show, don't list.** A visual beats a bullet: logos instead of tool names, flows with a moving pulse,
counting numbers, growing bars, characters acting a scene. One idea per slide; at most four cards in a
row; balance the slide vertically.

**Navigation.** Page dots on the left with hover labels, a top progress bar, bottom controls that fade
when idle, arrows, Space and swipe to move, F for full screen, O for overview, `#N` deep links.

**Delivery.** One HTML file that opens offline, with every image and video inside it and no external
URLs. Check every slide in a real browser before handing it over, and report the file's path and size.

## Reference

| File | Contents |
|---|---|
| `references/design-system.md` | Colour tokens, entity accents, type scale, layout, surfaces, media, chrome |
| `references/motion.md` | Motion rules, timings, background, playful mode, keys |
| `assets/template.html` | The reference implementation to start from |
