---
name: deck-guizang-editorial
emoji: "🖋️"
description: "E-magazine × e-ink: 10 layouts and 5 palettes (Monocle ink, Indigo Porcelain, Forest Ink, Kraft Paper, Dune)"
category: slides
scenario: marketing
aspect_hint: "16:9 horizontal page turns"
featured: 49
recommended: 1
tags: ["editorial", "e-ink", "magazine", "narrative", "guizang"]
example_id: sample-guizang-editorial
example_name: "Guizang Editorial · Chapter Opener"
example_format: markdown
example_tagline: "Monocle ink palette + serif display"
example_desc: "L02 Act Divider chapter opener + L03 Big Numbers Grid, printed-paper feel"
example_source_url: "https://github.com/op7418/guizang-ppt-skill"
example_source_label: "op7418/guizang-ppt-skill"
---

【Template: Guizang Editorial E-Ink Deck (Editorial × E-Ink)】
【Intent】Narratives, opinions, talks, personal style. A printed-ink-on-paper feel, not a tech feel. Inspired by op7418/guizang-ppt-skill Style A.

【Palette — pick 1 of 5. Do NOT change the hex values, do NOT mix palettes】
- 🖋 **Monocle Ink** — ink `#0a0a0b`, paper `#f1efea`, paper-tint `#e8e5de`, ink-tint `#18181a`. Default / general business / tech.
- 🌊 **Indigo Porcelain** — ink `#0a1f3d`, paper `#f1f3f5`, paper-tint `#e4e8ec`, ink-tint `#152a4a`. Tech / research / data.
- 🌿 **Forest Ink** — ink `#1a2e1f`, paper `#f5f1e8`, paper-tint `#ece7da`, ink-tint `#253d2c`. Nature / sustainability / culture.
- 🍂 **Kraft Paper** — ink `#2a1e13`, paper `#eedfc7`, paper-tint `#e0d0b6`, ink-tint `#3a2a1d`. Nostalgia / humanities / literature.
- 🌙 **Dune** — ink `#1f1a14`, paper `#f0e6d2`, paper-tint `#e3d7bf`, ink-tint `#2d2620`. Art / design / fashion.

【Layouts — a pool of 10 reusable layouts. The **number of slides is decided by the [user content]**: cover every point fully. Short content starts at 6-12 slides; long content should have more. The same layout may repeat in different chapters】
- **L01 Hero Cover** — centered large hero typography + kicker + subtitle + lead paragraph + bottom metadata row.
- **L02 Act Divider** — kicker + giant 8.5-10vw headline + one short quote. Chapter breaks may invert colors (ink ↔ paper).
- **L03 Big Numbers Grid** — 3×2 data cards (label / big number / note).
- **L04 Quote + Image** — left: kicker + headline + body + callout; right: 16:10 image (align to the baseline, not the top).
- **L05 Image Grid** — 3×2 or 3×1 grid of equal-height images (26vh or 22vh). Height must be strictly uniform.
- **L06 Pipeline / Flow** — horizontal group of numbered steps. Each step: №X + title + description. Supports stepping through with the keyboard.
- **L07 Hero Question** — one question, full-screen at 7vw, broken into lines by meaning, minimal surroundings.
- **L08 Big Quote** — giant 5.8vw serif quote + translation line + attribution + date.
- **L09 Before / After** — 1:1 split. Left column at opacity .55 (old / before); right column at full brightness (new / after).
- **L10 Mixed Media** — 8:4 ratio. Large text block on the left (kicker / headline / body / callout) + a 3:4 portrait image on the right as support.

【Design details】
- **Forbidden**: gradients / drop-shadow / rounded corners / circular decoration / blur / SVG icon libraries / emoji decoration.
- **Fonts**: display `Playfair Display` (English) / `Noto Serif SC` (Chinese); body `Inter` / `Noto Sans SC`; numbers and figures may occasionally use italic serif.
- **Magazine details**: kicker at 11px uppercase with 0.12em letter-spacing; folio at the bottom right, `01 / 12`; a thin hairline rule at the top plus the journal logo / topic.
- **Not allowed**: fabricated data, Lorem ipsum, placeholder image URLs. Draw all pictures with pure CSS or inline SVG (color blocks + simple line drawings).
- Keys ← / → switch slides; the hash stays in sync; single-file HTML.
