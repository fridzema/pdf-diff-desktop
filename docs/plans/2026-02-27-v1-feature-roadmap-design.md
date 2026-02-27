# PDF Diff Desktop — v1.0 Feature Roadmap Design

**Date:** 2026-02-27
**Goal:** Close competitive gaps with enterprise prepress tools while leveraging AI differentiation. Ship a credible standalone prepress QC tool that works offline + differentiates with AI analysis.

**Target users:** Commercial print shops, packaging prepress, design agencies — both packaging and commercial print workflows.

**Strategy:** Deterministic checks for things that MUST be exact. AI for subjective analysis and client-facing reports. Each feature works standalone and ships incrementally.

---

## 1. Preflight Engine (Rust Core)

New `preflight/` module alongside `diff/` and `engine/`. Returns `PreflightResult` with categorized findings. Exposed via UniFFI. Sub-second execution — uses MuPDF PDF object access, not rendering.

### Checks

| Check | Method | Severity |
|---|---|---|
| Font embedding | Parse PDF font dictionaries. Flag Type3, non-embedded, subset-only. | Fail if missing, Warn if subset |
| Image resolution | Extract image DPI from content streams. Configurable threshold (default 300). | Warn <300, Fail <150 |
| Color space validation | Detect RGB in CMYK workflows, mixed spaces, device-dependent colors. | Warn for RGB in print, Fail for device-dependent |
| Bleed/trim/media boxes | Read page box definitions. Flag missing bleed, insufficient bleed (<3mm), trim vs media mismatch. | Fail if no bleed, Warn if <3mm |
| Spot colors | List all spot color names. Flag unnamed, duplicates. | Info |
| Transparency | Detect transparency groups, soft masks, blend modes. | Info |
| Page consistency | Check all pages same size, same orientation. | Warn on mismatch |
| Overprint detection | Inspect graphics state operators for OPM mode, knockout vs overprint settings. | Warn when overprint detected |
| Ink coverage | Render per-separation, analyze pixel values. Sum CMYK at each pixel. Flag areas exceeding max ink limit (configurable, default 300%). | Warn >300%, Fail >340% |

### Data Model (Rust)

```rust
struct PreflightResult {
    checks: Vec<PreflightCheck>,
    summary: PreflightSummary,
}

struct PreflightCheck {
    category: PreflightCategory,
    severity: PreflightSeverity,  // Pass, Warn, Fail, Info
    title: String,
    detail: String,
    page: Option<u32>,           // Which page, if page-specific
}

enum PreflightCategory {
    Fonts, Images, ColorSpace, PageBoxes, SpotColors,
    Transparency, PageConsistency, Overprint, InkCoverage,
}

struct PreflightSummary {
    pass_count: u32,
    warn_count: u32,
    fail_count: u32,
    info_count: u32,
}
```

---

## 2. Preflight Panel (Inspector UI)

Collapsible panel in InspectorView, between page canvas and metadata panel. Replaces static metadata panel with a richer "Document Info" area.

### Layout

```
┌─────────────────────────────────────────┐
│ [< Page 1 of 4 >] [Zoom] [Inspect]     │  toolbar
├─────────────────────────────────────────┤
│                                         │
│           Page canvas + pins            │  ZoomableContainer
│                                         │
├─────────────────────────────────────────┤
│ Preflight: 5 pass, 2 warn, 1 fail      │  summary bar
│ ▶ Fonts (pass)                          │
│ ▼ Images (warn)                         │  expandable checks
│   └─ Page 3: 150 DPI (expected 300)     │
│ ▼ Ink Coverage (fail)                   │
│   └─ Page 1: 352% max (limit 340%)     │
│ ▶ Metadata                              │  existing metadata panel
└─────────────────────────────────────────┘
```

### Behavior

- Runs automatically on document load (fast, <1s)
- Summary bar shows aggregated pass/warn/fail counts
- Each category is a disclosure group with individual findings
- Clickable page references navigate to that page
- Color-coded: green checkmark (pass), yellow triangle (warn), red circle (fail), blue info (info)
- Works completely offline — no API key required

---

## 3. Separation Preview

New mode in Inspector view. Segmented control: "Page | Separations".

### Features

- Renders page as individual separations: C, M, Y, K + spot colors
- Each separation shown as grayscale plate (darker = more ink)
- Toggle checkboxes to enable/disable individual separations
- Composite view: all enabled separations combined
- Ink coverage percentage displayed per channel
- Total ink overlay: highlight areas exceeding max ink limit with a color wash

### Architecture

- Wire existing `render_separation(page, index, dpi)` in Rust (trait method exists, needs MuPDF implementation)
- Each separation renders to grayscale bitmap
- Swift composites using CoreImage (GPU-accelerated)
- Separation list comes from `separations(page)` (currently returns placeholders — needs real MuPDF wiring)

### UI

```
┌─────────────────────────────────────────┐
│ [Page | Separations]  [Zoom]            │
├─────────────────┬───────────────────────┤
│                 │ ☑ Cyan      42%       │
│   Composite     │ ☑ Magenta   38%       │
│   Preview       │ ☑ Yellow    45%       │
│                 │ ☑ Black     91%       │
│                 │ ☑ Pantone   12%       │
│                 │─────────────────────  │
│                 │ Max ink: 228%         │
└─────────────────┴───────────────────────┘
```

---

## 4. Barcode Detection

Uses Apple's Vision framework (`VNDetectBarcodesRequest`) on the rendered page image. Swift-side only, no Rust work.

### Features

- Detect and decode barcodes/QR codes in rendered page
- Highlight detected barcodes as rectangular regions on page canvas
- Display decoded data and symbology type (EAN-13, UPC-A, Code 128, QR, DataMatrix, etc.)
- Results shown in preflight panel as "Barcodes" section

### Scope (v1.0)

- Detection and decoding only
- No ISO/CEN/ANSI quality grading
- No barcode regeneration
- Output: "Found 2 barcodes: EAN-13 (5901234123457), QR (https://example.com)"

### Architecture

- `BarcodeDetectionService` in Swift using Vision framework
- Runs on the rendered `NSImage` after page render
- Returns array of `DetectedBarcode` (symbology, payload, bounding rect)
- Integrates with preflight results panel
- Bounding rects shown as overlay on page canvas (similar to issue pins)

---

## 5. Report Generation

Consolidated QC report combining all results into a shareable document.

### Report Sections

1. **Document summary** — filename, page count, metadata
2. **Preflight results** — all checks with pass/warn/fail and details
3. **Barcode results** — detected barcodes with decoded data
4. **Comparison results** (compare mode) — similarity score, changed regions, text diffs
5. **AI analysis** (if available) — visual changes, QC checklist, anomalies
6. **Page thumbnails** with annotated issue locations

### Export Formats

- **PDF** — professional layout via PDFKit (programmatic page creation). Suitable for client delivery.
- **Markdown** — for copy-paste into email, Slack, PM tools. Extends existing "Copy Report" functionality.

### Architecture

- `ReportGenerator` service in Swift
- Takes all result objects (`PreflightResult`, `[DetectedBarcode]`, `PDFDiffResult`, `AIAnalysisResult`, `InspectionResult`) and produces output
- Remove Rust `generate_report()` stub — Swift is the right place (has AI results + NSImages)
- "Export Report" button in both Inspector and Compare toolbars
- Save dialog with format picker (PDF / Markdown)

### AI-Enhanced Reports (Optional)

When an API key is configured, optionally include an AI narrative section:
- AI summarizes all findings in plain language
- Example: "The revised artwork corrected the barcode placement but introduced a color shift in the logo area. Font embedding is complete. Recommend approval with note about logo color."
- This is the differentiator — deterministic checks provide data, AI writes the human-readable summary

---

## 6. Batch Comparison

Process multiple document pairs in one operation.

### Features

- Drop a folder or select multiple document pairs
- Auto-match files by name similarity ("artwork_v1.pdf" ↔ "artwork_v2.pdf")
- Run pixel diff + preflight on each pair
- Results table: filename, similarity score, preflight status (pass/warn/fail count)
- Click row to open full comparison view
- "Export Batch Report" — single PDF covering all pairs

### UI

New tab or view mode alongside Inspector and Compare:

```
┌──────────────────────────────────────────────┐
│ [Inspector | Compare | Batch]                │
├──────────────────────────────────────────────┤
│ Drop folder or select files...               │
├──────┬──────────┬───────────┬────────────────┤
│ Pair │ Similarity│ Preflight │ Status         │
├──────┼──────────┼───────────┼────────────────┤
│ v1↔v2│ 94.2%    │ 3P 1W 0F  │ ✓ Complete    │
│ v3↔v4│ 87.1%    │ 2P 0W 2F  │ ✓ Complete    │
│ v5↔v6│ —        │ —         │ ⏳ Processing  │
└──────┴──────────┴───────────┴────────────────┘
│ [Export Batch Report]                        │
└──────────────────────────────────────────────┘
```

---

## 7. Finishing Remaining Tasks

### LRU Cache (Task 18)

- Cap rendered page cache at ~500MB
- Evict oldest entries when limit exceeded
- Track cache size in `MockPDFService` / future real service
- Important for batch mode (many pages rendered in sequence)

### Edge Cases (Task 19)

- Very large PDFs (>100 pages): lazy rendering, progress indication
- Encrypted/password-protected: clear error message, skip preflight
- Corrupted files: graceful degradation, partial results where possible
- Mixed page sizes: handle per-page rather than assuming uniform

---

## Feature Priority Order

1. **Preflight engine** (Rust) — foundation for everything
2. **Preflight panel** (Swift UI) — makes preflight visible
3. **Barcode detection** (Swift/Vision) — quick win, high value for packaging
4. **Separation preview** (Rust + Swift) — visual differentiator
5. **Report generation** (Swift) — client communication
6. **Batch comparison** (Swift) — power user workflow
7. **LRU cache + edge cases** — polish for v1.0 release

---

## What's Deliberately Excluded (YAGNI)

- Braille inspection (too specialized for v1.0)
- Spell check (Apple's built-in exists)
- PDF/X full conformance (complex spec, diminishing returns)
- OCR (adds complexity without clear v1.0 value)
- Overprint simulation/compositing (complex, defer to v1.1)
- Barcode ISO grading (v1.0 does detection only)
- Cross-platform (macOS-only by design)
