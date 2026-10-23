---
name: doc-kami-parchment
emoji: "📜"
description: "Warm parchment ground (#f5f4ed) + single ink-blue accent (#1B365D) + one serif typeface: editorial-grade typesetting"
category: doc
scenario: personal
aspect_hint: "A4 / Letter long pages"
featured: 48
recommended: 3
tags: ["kami", "parchment", "serif", "editorial", "report", "letter", "one-pager"]
example_id: sample-kami-parchment
example_name: "Kami Parchment · One-Pager"
example_format: markdown
example_tagline: "Warm parchment + single ink blue + single serif"
example_desc: "An editorial one-pager, Open Design Studio Issue №26"
example_source_url: "https://github.com/tw93/kami"
example_source_label: "tw93/kami"
---

【Template: Kami Parchment Document】
【Intent】Serious typeset documents: one-pager / long report / letter / resume / financial report / changelog / portfolio. Inspired by tw93/kami. The goal is a page that looks typeset for print: not a dashboard, not a web page.

【Fixed visual signature — do not change】
- **Canvas**: warm parchment `#f5f4ed` (never pure white `#fff`). Secondary background `#efeee5`.
- **Ink**: main text `#1f1d18` (near-black warm grey, not pure black `#000`). Secondary text `#6b665b`.
- **Only color**: ink blue `#1B365D`. Every accent (links, tag outlines, key figures, the left rule of a quote) uses this one color only. No other colors.
- **Typeface**: one serif per language, never mixed within a document:
  - English: `Charter` (fallbacks: `Source Serif Pro`, `Iowan Old Style`)
  - Chinese: `TsangerJinKai02 W04` (fallback: `Noto Serif SC`)
  - Japanese: `YuMincho` (fallback: `Noto Serif JP`)
  - Body 400, headings 500 (not 700/800/900).
- **Line height**: headings 1.1–1.3; compact body 1.4–1.45; reading body 1.5–1.55.
- **Never**: drop-shadow / blur / border-radius ≥ 8px / gradients / neon colors / rgba (use solid hex).
- **Details**: tags are solid-hex background blocks (WeasyPrint does not render rgba well); single-line geometric icons; 1px hairline rules in `#d4d1c5`, controlled in length and not running edge to edge.

【Optional document types — choose by the user content】
- **One-Pager** — top logotype (Charter italic) + title + lede + 3-column key points + footer metadata.
- **Long Doc** — cover page (large title + subtitle + author + date) → table of contents (kicker + page no.) → chapters (folio at the top corner + section rule + body) → endnote footnotes + colophon at the end.
- **Letter** — sender address + date + recipient + body (left-aligned, 1.5em between paragraphs) + sign-off + signature line.
- **Portfolio** — project hero (large title + sub) + one full-width image (a placeholder drawn with CSS blocks) + project description + metadata row for role / time / stack.
- **Resume** — name at the top (large) + one-line tagline + contact row + main sections: experience (company / dates / role / bullets) + skills + education.
- **Slides** — keynote style. The page count is decided by the [user content] (short content starts at 6 pages; long content should have more). Each page is filled with parchment, a large title + lede, and a page number in the corner. Keep it so simple it feels printed.
- **Equity Report** — company name + ticker + quarter × year + key metrics row (revenue / margin / YoY) + analysis body + chart (single-color SVG line).
- **Changelog** — version number (large Charter italic) + date + list of changes (Added / Changed / Fixed), separated by a single rule.

【Design principles】
- "Composed pages, not dashboards." Do not stack KPI cards, do not stack emoji icons, no gradient heroes.
- "Ring or whisper only, no hard drop shadows." Shadows may only be hairline outlines such as `0 0 0 1px #d4d1c5`.
- Hierarchy comes from **serif contrast + size + whitespace**, not from color.
- Single HTML file using the Tailwind CDN. When Chinese and English are mixed in the text, add spacing between them (pangu-style). No external images; use paper-tint color blocks with a 1px ink outline as placeholders.
