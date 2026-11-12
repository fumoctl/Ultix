# Compositional `docx-js` & OpenXML Primitives

Reusable, token-driven building blocks for `docx` (`v9.x`). Adapt and recombine these primitives to fit each document's bespoke design — do not treat them as a mandatory checklist.

---

## 1. Units & Page Geometry Cheat Sheet

- **DXA (twentieths of a point):** `1 inch = 1440 DXA`, `1 pt = 20 DXA`, `1 cm ≈ 567 DXA`.
- **Paragraph `spacing.line`:** When `lineRule` is omitted (`auto`), `line` is in **240ths of a line** (`240 = 1.0x` single spacing, `264 = 1.1x`, `288 = 1.2x`) — **not** DXA! Never pass large DXA numbers (e.g. `620`) on display headings unless `lineRule: LineRuleType.EXACT` is explicitly set.
- **Font `size`:** Half-points (`20 = 10pt`, `24 = 12pt`, `36 = 18pt`).
- **Border `size`:** Eighths of a point (`4 = 0.5pt` hairline, `8 = 1pt`, `24 = 3pt` accent bar).
- **`ImageRun` `transformation`:** Pixels at **96 DPI** (`1 inch = 96 px`, so `6.5 inches = 624 px` max full-column width on US Letter with 1" margins; `6.27 inches = 602 px` on A4 with 1" margins).
- **Standard Printable Widths (with 1" = `1440` DXA left/right margins):**
  - **A4 (`11906 × 16838` DXA):** Printable width = `9026` DXA (`~602` px in `ImageRun`).
  - **US Letter (`12240 × 15840` DXA):** Printable width = `9360` DXA (`624` px in `ImageRun`).

---

## 2. Proportional Image Helper (`image-size`)

`image-size` is pre-installed in `scripts/run-docx-js.sh`. Always read actual PNG pixel dimensions so diagrams and custom SVG figures never stretch or overflow the page:

```javascript
const fs = require("fs");
const sizeOf = require("image-size");
const { ImageRun, Paragraph, AlignmentType } = require("docx");

/**
 * Scale a PNG proportionally to fit within maxWidthPx and maxHeightPx (96-DPI units).
 * High-DPI (@3x) PNGs look razor-sharp when displayed at 1/3 pixel dimensions.
 */
function figureImageRun(pngPath, { maxWidthPx = 600, maxHeightPx = 680, sourceScale = 3 } = {}) {
  const buf = fs.readFileSync(pngPath);
  const dims = sizeOf(buf);
  let w = dims.width / sourceScale;
  let h = dims.height / sourceScale;

  if (w > maxWidthPx) {
    const r = maxWidthPx / w;
    w *= r;
    h *= r;
  }
  if (h > maxHeightPx) {
    const r = maxHeightPx / h;
    w *= r;
    h *= r;
  }
  return new ImageRun({
    type: "png",
    data: buf,
    transformation: { width: Math.round(w), height: Math.round(h) },
  });
}

function captionedFigure(pngPath, captionText, tokens, opts = {}) {
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      keepNext: true,
      spacing: { before: 240, after: 100 },
      children: [figureImageRun(pngPath, opts)],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 0, after: 260 },
      children: [
        new TextRun({
          text: captionText,
          italics: true,
          size: 18,
          font: tokens.bodyFont,
          color: tokens.muted,
        }),
      ],
    }),
  ];
}
```

---

## 3. Multi-Section Document Skeleton (Distinct Cover + Running Headers/Footers)

Separate the **Cover Page** into Section 1 (no running header/footer, custom margins) and the **TOC + Body** into Section 2 (running header/footer with right-aligned `TabStopType.RIGHT` + `"\t"` and page numbers — prefer `TabStopType.RIGHT` over `PositionalTab`, because LibreOffice collapses `<w:ptab>` in headers/footers while `TabStopType.RIGHT` renders flush-right everywhere; add `leader: LeaderType.DOT` for TOC/directory dot leaders):

```javascript
const {
  Document, Packer, Paragraph, TextRun, Header, Footer,
  PageNumber, TabStopType, LeaderType,
  HeadingLevel, TableOfContents, BorderStyle, LevelFormat, AlignmentType
} = require("docx");

function runningHeader(docTitle, sectionTag, contentWidthDxa, tokens) {
  return new Header({
    children: [
      new Paragraph({
        spacing: { after: 120 },
        tabStops: [{ type: TabStopType.RIGHT, position: contentWidthDxa }],
        border: {
          bottom: { style: BorderStyle.SINGLE, size: 4, color: tokens.border, space: 6 },
        },
        children: [
          new TextRun({ text: docTitle, font: tokens.bodyFont, size: 16, color: tokens.muted }),
          new TextRun({ text: `\t${sectionTag}`, font: tokens.bodyFont, size: 16, color: tokens.muted }),
        ],
      }),
    ],
  });
}

function runningFooter(leftNote, contentWidthDxa, tokens) {
  return new Footer({
    children: [
      new Paragraph({
        spacing: { before: 120 },
        tabStops: [{ type: TabStopType.RIGHT, position: contentWidthDxa }],
        border: {
          top: { style: BorderStyle.SINGLE, size: 4, color: tokens.border, space: 6 },
        },
        children: [
          new TextRun({ text: leftNote, font: tokens.bodyFont, size: 16, color: tokens.muted }),
          new TextRun({
            children: ["\tPage ", PageNumber.CURRENT, " of ", PageNumber.TOTAL_PAGES],
            font: tokens.bodyFont,
            size: 16,
            color: tokens.muted,
          }),
        ],
      }),
    ],
  });
}
```

Assemble the `Document` with `features: { updateFields: true }` so Word/EuroOffice prompts or updates dynamic TOC and page-count fields cleanly:

```javascript
const doc = new Document({
  features: { updateFields: true },
  numbering: {
    config: [
      {
        reference: "doc-bullets",
        levels: [
          {
            level: 0,
            format: LevelFormat.BULLET,
            text: "▪",
            alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 480, hanging: 240 } } },
          },
          {
            level: 1,
            format: LevelFormat.BULLET,
            text: "◦",
            alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 840, hanging: 240 } } },
          },
        ],
      },
    ],
  },
  styles: {
    default: {
      document: {
        run: { font: tokens.bodyFont, size: 21, color: tokens.ink },
        paragraph: { spacing: { line: 288, after: 140 } },
      },
    },
    paragraphStyles: [
      {
        id: "Heading1",
        name: "Heading 1",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: tokens.displayFont, size: 34, bold: true, color: tokens.primary },
        paragraph: { spacing: { before: 420, after: 160 }, keepNext: true, outlineLevel: 0 },
      },
      {
        id: "Heading2",
        name: "Heading 2",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: tokens.displayFont, size: 26, bold: true, color: tokens.primary },
        paragraph: { spacing: { before: 320, after: 120 }, keepNext: true, outlineLevel: 1 },
      },
      {
        id: "Heading3",
        name: "Heading 3",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: tokens.displayFont, size: 22, bold: true, color: tokens.ink },
        paragraph: { spacing: { before: 240, after: 80 }, keepNext: true, outlineLevel: 2 },
      },
    ],
  },
  sections: [
    {
      properties: {
        page: {
          size: { width: 11906, height: 16838 }, // A4 (use 12240 x 15840 for US Letter)
          margin: { top: 1200, bottom: 1200, left: 1440, right: 1440 },
        },
      },
      children: coverChildren, // Section 1: Cover page only
    },
    {
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 },
        },
      },
      headers: { default: runningHeader(title, category, 9026, tokens) },
      footers: { default: runningFooter(footerNote, 9026, tokens) },
      children: bodyChildren, // Section 2: TOC + main content
    },
  ],
});
```

---

## 4. Layout & Content Primitives

### A. Borderless Grid / Multi-Column Showcase Table

Use borderless `DXA`-sized tables to create **asymmetric covers**, **KPI stat strips**, or **side-by-side Figure + Analysis cards**:

```javascript
const { Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType, VerticalAlign } = require("docx");

const NO_BORDER = { style: BorderStyle.NONE, size: 0, color: "FFFFFF" };
const NO_BORDERS = {
  top: NO_BORDER, bottom: NO_BORDER, left: NO_BORDER, right: NO_BORDER,
  insideHorizontal: NO_BORDER, insideVertical: NO_BORDER,
};

function kpiStrip(metrics, totalWidthDxa, tokens) {
  const gapDxa = 140;
  const n = metrics.length;
  const cardWidth = Math.floor((totalWidthDxa - gapDxa * (n - 1)) / n);
  const colWidths = [];
  const cells = [];

  metrics.forEach((m, idx) => {
    colWidths.push(cardWidth);
    cells.push(
      new TableCell({
        width: { size: cardWidth, type: WidthType.DXA },
        shading: { type: ShadingType.CLEAR, color: "auto", fill: tokens.surface },
        margins: { top: 180, bottom: 180, left: 200, right: 200 },
        borders: {
          top: { style: BorderStyle.SINGLE, size: 18, color: tokens.accent },
          bottom: NO_BORDER, left: NO_BORDER, right: NO_BORDER,
        },
        children: [
          new Paragraph({
            spacing: { after: 40 },
            children: [
              new TextRun({ text: m.value, font: tokens.displayFont, size: 36, bold: true, color: tokens.primary }),
            ],
          }),
          new Paragraph({
            spacing: { after: 0 },
            children: [
              new TextRun({ text: m.label, font: tokens.bodyFont, size: 17, color: tokens.muted }),
            ],
          }),
        ],
      })
    );
    if (idx < n - 1) {
      colWidths.push(gapDxa);
      cells.push(
        new TableCell({
          width: { size: gapDxa, type: WidthType.DXA },
          borders: NO_BORDERS,
          children: [new Paragraph({})],
        })
      );
    }
  });

  return new Table({
    width: { size: colWidths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths: colWidths,
    borders: NO_BORDERS,
    rows: [new TableRow({ cantSplit: true, children: cells })],
  });
}
```

### B. Left-Accent Callout Box & Monospace Code Block

```javascript
function calloutBox(leadTitle, bodyText, widthDxa, tokens, borderColor = tokens.accent) {
  return new Table({
    width: { size: widthDxa, type: WidthType.DXA },
    columnWidths: [widthDxa],
    rows: [
      new TableRow({
        cantSplit: true,
        children: [
          new TableCell({
            width: { size: widthDxa, type: WidthType.DXA },
            shading: { type: ShadingType.CLEAR, color: "auto", fill: tokens.surface },
            margins: { top: 160, bottom: 160, left: 240, right: 220 },
            borders: {
              left: { style: BorderStyle.SINGLE, size: 24, color: borderColor },
              top: NO_BORDER, right: NO_BORDER, bottom: NO_BORDER,
            },
            children: [
              new Paragraph({
                spacing: { after: 0 },
                children: [
                  new TextRun({ text: `${leadTitle}: `, bold: true, font: tokens.bodyFont, size: 20, color: tokens.primary }),
                  new TextRun({ text: bodyText, font: tokens.bodyFont, size: 20, color: tokens.ink }),
                ],
              }),
            ],
          }),
        ],
      }),
    ],
  });
}

function codeBlock(lines, widthDxa, tokens) {
  return new Table({
    width: { size: widthDxa, type: WidthType.DXA },
    columnWidths: [widthDxa],
    rows: [
      new TableRow({
        cantSplit: true,
        children: [
          new TableCell({
            width: { size: widthDxa, type: WidthType.DXA },
            shading: { type: ShadingType.CLEAR, color: "auto", fill: tokens.codeBg || tokens.surface },
            margins: { top: 140, bottom: 140, left: 200, right: 200 },
            borders: {
              top: { style: BorderStyle.SINGLE, size: 4, color: tokens.border },
              bottom: { style: BorderStyle.SINGLE, size: 4, color: tokens.border },
              left: { style: BorderStyle.SINGLE, size: 4, color: tokens.border },
              right: { style: BorderStyle.SINGLE, size: 4, color: tokens.border },
            },
            children: lines.map(
              (line) =>
                new Paragraph({
                  spacing: { line: 240, after: 0 },
                  children: [
                    new TextRun({
                      text: line || " ",
                      font: tokens.monoFont,
                      size: 17,
                      color: tokens.codeInk || tokens.ink,
                    }),
                  ],
                })
            ),
          }),
        ],
      }),
    ],
  });
}
```

### C. Repeating-Header Data Table (`tableHeader: true`, Dual `DXA` Widths)

Always set explicit `columnWidths` on the `Table` **and** matching `width` on every `TableCell` in `WidthType.DXA`:

```javascript
function styledDataTable(headers, rows, colWidths, tokens) {
  const totalWidth = colWidths.reduce((a, b) => a + b, 0);
  const thinBorder = { style: BorderStyle.SINGLE, size: 4, color: tokens.border };

  const headerRow = new TableRow({
    tableHeader: true,
    cantSplit: true,
    children: headers.map((h, i) =>
      new TableCell({
        width: { size: colWidths[i], type: WidthType.DXA },
        shading: { type: ShadingType.CLEAR, color: "auto", fill: tokens.primary },
        margins: { top: 120, bottom: 120, left: 150, right: 150 },
        verticalAlign: VerticalAlign.CENTER,
        borders: { top: thinBorder, bottom: thinBorder, left: NO_BORDER, right: NO_BORDER },
        children: [
          new Paragraph({
            spacing: { after: 0 },
            children: [new TextRun({ text: h, bold: true, font: tokens.bodyFont, size: 18, color: "FFFFFF" })],
          }),
        ],
      })
    ),
  });

  const bodyRows = rows.map((row, rIdx) =>
    new TableRow({
      cantSplit: true,
      children: row.map((cellText, cIdx) =>
        new TableCell({
          width: { size: colWidths[cIdx], type: WidthType.DXA },
          shading:
            rIdx % 2 === 1
              ? { type: ShadingType.CLEAR, color: "auto", fill: tokens.surface }
              : undefined,
          margins: { top: 100, bottom: 100, left: 150, right: 150 },
          verticalAlign: VerticalAlign.TOP,
          borders: { top: NO_BORDER, bottom: thinBorder, left: NO_BORDER, right: NO_BORDER },
          children: [
            new Paragraph({
              spacing: { line: 252, after: 0 },
              children: [
                new TextRun({
                  text: String(cellText),
                  bold: cIdx === 0,
                  font: tokens.bodyFont,
                  size: 18,
                  color: tokens.ink,
                }),
              ],
            }),
          ],
        })
      ),
    })
  );

  return new Table({
    width: { size: totalWidth, type: WidthType.DXA },
    columnWidths: colWidths,
    rows: [headerRow, ...bodyRows],
  });
}
```

---

## 5. Editing Existing `.docx` Files Safely

`docx-js` only creates new files. When modifying an existing `.docx` or `.dotx` while preserving its styles/media:

1. Unpack into `/tmp/docx-edit-xxx`:
   ```bash
   WORK=$(mktemp -d /tmp/docx-edit.XXXXXX)
   unzip -q input.docx -d "$WORK/unpacked"
   find "$WORK/unpacked" -type l -delete
   ```
2. Inspect and modify `$WORK/unpacked/word/document.xml` via `python3` (`xml.etree.ElementTree` or `xml.dom.minidom` **without** pretty-printing/adding whitespace text nodes inside `<w:t>`). Remember Word often splits visible phrases across adjacent `<w:r>` runs.
3. Repack cleanly without parent directory prefixes:
   ```bash
   (cd "$WORK/unpacked" && zip -q -Xr /abs/path/to/output.docx .)
   ```
4. Visually verify with `scripts/render-pages.sh /abs/path/to/output.docx "$WORK/qa"`.
