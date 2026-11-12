# Generative Art Direction for Word Documents

Never reuse a single rigid template across unrelated briefs. Approach every document as a studio design lead: derive the color tokens, typographic voice, cover composition, and visual components directly from the subject matter, audience, and communicative purpose.

---

## 1. Pass 1: Subject-Grounded Design Brief (Before Coding)

Before writing a `docx-js` script, establish a compact **Design Token Spec**:

1. **Audience & Archetype:** Identify what this document *is* and how it will be read:
   - *Systems / Engineering Specification:* Precision rules, crisp grotesque sans + technical mono, dense specifications, sequence/ER/architecture diagrams, high-signal callouts.
   - *Editorial Whitepaper / Academic Monograph:* Generous margins, literary serif body + high-contrast display face, hairline horizontal rules (booktabs tables), restrained ink/paper palette, minimal chrome.
   - *Executive Strategy / Financial Memo:* Authoritative deep primary (slate, forest, oxblood, midnight), metric summary strip, structured decision matrices, asymmetric split cover.
   - *Product Proposal / Design Pitch:* Expressive cover art (custom SVG geometry or Playwright canvas), 2-column visual showcase cards, process ribbons, energetic accent color.
   - *Security Audit / Operational Runbook:* Severity-coded badges, structured finding cards with metadata header bars, numbered procedural blocks.

2. **6-Color Token System:** Define 6 harmonious hex colors. Keep two representations in code (`#HEX` for SVG/Mermaid/D2/CSS, bare `HEX` without `#` for `docx-js`):
   - `primary`: Dominant brand/structural color (headings, cover anchor, table headers).
   - `accent`: High-contrast focal highlight used sparingly (call-to-attention borders, key metrics, diagram highlights).
   - `ink`: Primary body text (deep neutral or tinted charcoal, e.g. `182026`, `1E1B18` — softer and richer than pure `000000`).
   - `muted`: Secondary metadata, captions, running headers/footers, subtle labels (e.g. `5C6B77`).
   - `surface`: Soft card/callout/alternating-row tint derived from `primary` at ~5–8% saturation (e.g. `F2F5F9`, `F6F4EF`).
   - `border`: Hairline divider and subtle table grid color (e.g. `D5DDE5`).

3. **Font Pairing & Typographic Scale:**
   - Pick 1–2 intentional font families plus a monospace face for code/schemas. Prefer fonts available system-wide on Linux/Cross-Platform so LibreOffice QA and desktop viewers render identical metrics (e.g., `Noto Sans` / `Noto Serif`, `Liberation Sans` / `Liberation Serif`, `DejaVu Sans` / `DejaVu Serif`, `JetBrainsMono Nerd Font` / `DejaVu Sans Mono`, or standard Office families when requested by the user).
   - Establish a clear hierarchy (`docx-js` `size` is in **half-points**, `24` = 12pt):
     - Cover Display: `52`–`76` (`26pt`–`38pt`), tight leading
     - Heading 1: `32`–`38` (`16pt`–`19pt`), `keepNext: true`, generous `spacing.before` (`360`–`480` DXA)
     - Heading 2: `25`–`28` (`12.5pt`–`14pt`), `keepNext: true`
     - Heading 3: `21`–`23` (`10.5pt`–`11.5pt`), `keepNext: true`
     - Body Copy: `20`–`22` (`10pt`–`11pt`), `spacing.line: 276`–`312` (1.15x–1.3x)
     - Tables & Captions: `17`–`19` (`8.5pt`–`9.5pt`)

4. **Cover Page Composition (Choose or Invent One Fitting the Brief):**
   - **Monolith Banner:** Deep `primary` hero block at top of page (or full-width custom SVG geometric header), bold contrast display title, subtitle, structured key-value metadata table below, executive abstract box, and TOC on page 2.
   - **Asymmetric Swiss Split:** 2-column borderless cover grid — narrow left rail (`~2600` DXA) holding vertical metadata/version/date/authors with a thick accent rule, wide right column (`~6760` DXA) holding display title, thesis statement, and a custom geometric SVG emblem.
   - **Minimalist Broadsheet:** Clean typographic lockup with generous top whitespace, hairline top/bottom rules, serif display title, centered or left-aligned author block, and framed abstract on page 1.
   - **Full-Canvas Illustrated Cover:** Custom vector SVG poster (`viewBox="0 0 800 460"` or full-page ratio) rendered at 3x via `render-svg.sh` combining architectural geometry, subtle grid lines, and typographic badges, paired with clean metadata underneath.

---

## 2. Self-Critique Against AI Clichés

Before building, check your design plan against common tells:
- **Spend boldness in one place:** Let the cover, diagram language, or section openers carry the visual signature; keep body pages calm, legible, and disciplined.
- **Don't box everything:** If every paragraph sits inside a shaded card, nothing stands out. Reserve callout boxes, KPI strips, and side-by-side showcase cards for moments where spatial structure communicates hierarchy.
- **Avoid robotic chrome:** Do not automatically slap tracked-out ALL-CAPS eyebrows above every heading or `01 / 02 / 03` badges on things that aren't sequential.
- **Match diagram orientation to portrait pages:** Wide horizontal (`LR`) flowcharts with 6+ stages shrink to unreadable 5pt text when fitted to a 6.5" portrait column. Prefer top-to-bottom (`TB`) flows, compact 2–3 column subgraphs, or multi-row pipelines so labels remain crisp at ~9–10pt on the printed page.

---

## 3. Unified Token Propagation Across Diagrams & Shapes

Every visual asset must share the document's exact palette and font family — never drop default purple/yellow Mermaid charts into a custom-designed document.

### A. Mermaid Theme Config (`render-mermaid.sh`)

Generate a `mermaid-config.json` per document using `"theme": "base"` and pass it as the 3rd argument to `render-mermaid.sh`:

```json
{
  "theme": "base",
  "flowchart": { "curve": "basis", "padding": 16, "nodeSpacing": 36, "rankSpacing": 44 },
  "sequence": { "mirrorActors": false, "messageMargin": 32, "boxMargin": 12 },
  "themeVariables": {
    "fontFamily": "Noto Sans, sans-serif",
    "fontSize": "14px",
    "primaryColor": "#F2F5F9",
    "primaryTextColor": "#182026",
    "primaryBorderColor": "#234E70",
    "lineColor": "#234E70",
    "secondaryColor": "#E6EEF5",
    "tertiaryColor": "#FAFBFD",
    "tertiaryBorderColor": "#D5DDE5",
    "mainBkg": "#F2F5F9",
    "nodeBorder": "#234E70",
    "clusterBkg": "#FAFBFD",
    "clusterBorder": "#B8C7D6",
    "titleColor": "#182026",
    "edgeLabelBackground": "#FFFFFF",
    "actorBkg": "#234E70",
    "actorTextColor": "#FFFFFF",
    "actorBorder": "#234E70",
    "actorLineColor": "#5C6B77",
    "signalColor": "#182026",
    "noteBkgColor": "#FFF8E6",
    "noteTextColor": "#182026",
    "noteBorderColor": "#D99B26",
    "attributeBackgroundColorOdd": "#FFFFFF",
    "attributeBackgroundColorEven": "#F2F5F9"
  }
}
```

*(Replace every hex above with your current document's `primary`, `accent`, `surface`, `ink`, `muted`, and `border` tokens.)*

### B. D2 Architecture Diagrams (`render-d2.sh`)

Use D2 when nested system containers, clean orthogonal routing, or `sql_table` shapes read cleaner than Mermaid (note: `stroke-width` in D2 must be an integer `0..15`, and setting `label.near: top-left` on containers prevents incoming top arrows from crossing centered titles):

```d2
direction: down
vars: {
  d2-config: {
    pad: 24
  }
}
classes: {
  box: {
    style: {
      fill: "#F2F5F9"
      stroke: "#234E70"
      stroke-width: 2
      font-color: "#182026"
      border-radius: 8
    }
  }
  highlight: {
    style: {
      fill: "#234E70"
      stroke: "#234E70"
      font-color: "#FFFFFF"
      border-radius: 8
    }
  }
}
```

### C. Custom Shapes, Infographics & Cover Graphics (`render-svg.sh` & `playwright` MCP)

Word's raw DrawingML XML shapes are rigid and verbose. Instead:
- **Vector Shapes, Process Ribbons, Timelines, Layered Stacks, Charts & Cover Art:** Author clean standalone `.svg` files with explicit `width`, `height`, `viewBox`, and your document's hex/font tokens, then rasterize at 3x via `scripts/render-svg.sh fig.svg fig.png 3`.
- **UI Mockups, Complex Multi-Card Infographics & Rich CSS Layouts:** Build an HTML/CSS mockup in `/tmp`, open it with the `playwright` MCP server (`browser_resize` + `browser_navigate` to `file:///tmp/...`), and capture high-DPI element/page screenshots (`browser_take_screenshot`) to embed inside 1-column figures or 2-column showcase grids.
