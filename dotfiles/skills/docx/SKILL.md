---
name: docx
description: >-
  Use this skill whenever the user wants to create, design, read, edit, or convert
  Microsoft Word (.docx or .dotx) documents, technical specifications, reports,
  whitepapers, proposals, memos, or formatted deliverables with custom palettes,
  title pages, tables, Mermaid/D2 architecture diagrams, custom shapes, or UI
  figures. Do NOT use for plain Markdown files, spreadsheets, or standalone PDFs.
---

# Generative DOCX Studio (Zero-Clutter Nix Pipeline)

Create publication-grade `.docx` documents with bespoke, topic-grounded visual identities — never a single rigid template — while keeping the user's workspace and `$HOME` completely free of `node_modules`, `package.json`, or dotfile clutter.

All CLI tools run ephemerally via `nix shell` through the helper scripts in `./scripts/`. Always stage scratch scripts, diagram sources, and QA page renders inside a disposable `/tmp/docx-work-XXXXXX` directory and write only the final `.docx` to the user's target path.

---

## 1. Ephemeral Toolchain (`./scripts/`)

Resolve script paths relative to this `SKILL.md` file's directory:

| Task | Command / Tool | Notes |
| :--- | :--- | :--- |
| **Build `.docx` via `docx-js`** | `[run-docx-js.sh](./scripts/run-docx-js.sh) /tmp/.../build.cjs` | Runs Node.js with `docx@^9.5` and `image-size@^1.2` pre-cached in `/tmp` — **never** run `npm install` in the user's project. |
| **Render Mermaid → 3x PNG** | `[render-mermaid.sh](./scripts/render-mermaid.sh) in.mmd out.png theme.json` | Headless Chromium (`mmdc -s 3`, transparent bg). Always pass a custom `theme.json` matching your document palette. |
| **Render D2 → 3x PNG** | `[render-d2.sh](./scripts/render-d2.sh) in.d2 out.png` | Fast, clean orthogonal architecture & SQL schema diagrams via `d2` + `resvg`. |
| **Render SVG Shapes → 3x PNG** | `[render-svg.sh](./scripts/render-svg.sh) in.svg out.png 3` | Rasterizes custom vector shapes, cover art, process ribbons, timelines, and charts at 3x DPI with system fonts. |
| **Render UI / HTML Figures** | **`playwright` MCP** (`browser_resize` + `browser_evaluate` + `browser_take_screenshot`) | `file://` is blocked in `playwright-mcp`; render HTML on `about:blank` via `browser_evaluate` (`document.write(...)`, `document.body.style.zoom = "3"`), screenshot (omit `filename` so it writes to `.playwright-mcp/`), move the PNG to `/tmp`, then `rm -rf .playwright-mcp` and `browser_close`. |
| **Visual QA & TOC Evaluation** | `[render-pages.sh](./scripts/render-pages.sh) out.docx /tmp/.../qa` | Headless LibreOffice (isolated `/tmp` profile) → PDF → `page-*.png` so you can inspect every page with `read_file`. |
| **Read Existing `.docx`** | `[read-docx.sh](./scripts/read-docx.sh) input.docx` | Extracts structured Markdown via `pandoc`. |

---

## 2. Three-Pass Workflow for Creating New Documents

### Pass 1: Invent a Subject-Grounded Design System
Read **[art-direction.md](./references/art-direction.md)** before writing code.
1. **Derive the aesthetic from the subject and audience** (e.g., *Swiss systems spec*, *editorial academic monograph*, *executive strategy memo*, *product pitch*).
2. **Define a 6-color token palette** (`primary`, `accent`, `ink`, `muted`, `surface`, `border`), a 1–2 family **font pairing + monospace face** (prefer installed cross-platform families like `Noto Sans`, `Noto Serif`, `Liberation Sans`, `JetBrainsMono Nerd Font`, `DejaVu Sans`), a clear **type scale**, and a **cover page composition** tailored to the brief.
3. **Self-critique before building:** Reject generic AI clichés (boxing every paragraph, slapping ALL-CAPS eyebrows on every heading, or squeezing wide 8-step `LR` flowcharts onto a portrait page where text shrinks below 8pt).

### Pass 2: Generate Visual Assets & Build the `.docx`
Read **[openxml-primitives.md](./references/openxml-primitives.md)** for composable `docx-js` patterns.
1. **Unify tokens across every visual medium:**
   - Generate `mermaid-theme.json` (`"theme": "base"` + `themeVariables`) from the exact same hex tokens before calling `render-mermaid.sh`.
   - Use `render-d2.sh` for nested container/schema diagrams or `render-svg.sh` / `playwright` MCP for custom vector shapes, cover illustrations, timelines, badges, and UI mockups.
2. **Respect critical `docx-js` OpenXML invariants:**
   - **Never embed raw `.svg` in `ImageRun`** (Word mangles SVG fonts/markers). Always rasterize to `@3x` PNG and compute exact proportional display dimensions with `image-size`.
   - **Dual `DXA` widths on every table:** Set `columnWidths` on the `Table` **and** matching `width: { size, type: WidthType.DXA }` on every `TableCell` (`PERCENTAGE` widths break across viewers). Column widths must sum to the printable width (`9026` DXA on A4 or `9360` DXA on US Letter with `1440` 1" margins).
   - **Shading:** Always `ShadingType.CLEAR` with 6-char hex `fill` (no `#` prefix in `docx-js`!). Never use `ShadingType.SOLID` (renders solid black).
   - **Pagination & flow:** Separate Cover (`Section 1`, no running header/footer) from Body (`Section 2`, running `Header`/`Footer` with `TabStopType.RIGHT` + `"\t"` + `PageNumber` — avoid `PositionalTab`, which LibreOffice collapses in headers/footers; use `LeaderType.DOT` for dot leaders). Remember `spacing.line` defaults to 240ths of a line (`240` = 1.0x), not DXA. Set `keepNext: true` on headings and figure paragraphs (so captions never orphan), `tableHeader: true` on table header rows, and `cantSplit: true` on data/callout rows.
   - **Lists & line breaks:** Use `numbering` configs (`LevelFormat.BULLET`), never literal `•` characters or `\n` inside `TextRun` (use separate `Paragraph`s).
   - **TOC:** Use built-in `HeadingLevel.*` (with `outlineLevel` on custom heading styles) and `features: { updateFields: true }`.

### Pass 3: Mandatory Visual QA Loop
Never deliver a generated `.docx` sight-unseen:
1. Run `./scripts/render-pages.sh <output.docx> /tmp/docx-work-xxx/qa`.
2. Call `read_file` on the rendered `page-*.png` images (always inspect the cover page, TOC, every diagram/figure page, and dense table pages).
3. Fix any visual defects — clipped diagram text, awkward page splits, orphaned captions, cramped cell padding, or low text-on-fill contrast — re-run the build script, and re-verify.
4. Remove temporary `/tmp/docx-work-xxx` scratch files when finished.

---

## 3. Reading & Editing Existing Documents

- **Inspect text/structure:** Run `./scripts/read-docx.sh file.docx`.
- **Modify an existing `.docx` without losing custom styles:** `docx-js` cannot open existing files. Follow Section 5 of **[openxml-primitives.md](./references/openxml-primitives.md)** (`unzip` in `/tmp` → edit `word/document.xml` carefully without pretty-printing XML → `zip -q -Xr` → verify visually with `./scripts/render-pages.sh`).
