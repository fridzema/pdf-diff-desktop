# PDF Diff Desktop — Design Document

**Date:** 2026-02-25
**Status:** Approved

## Purpose

A macOS-native desktop application for DTP operators and Quality Control professionals to inspect individual PDFs and visually/structurally compare pairs of PDFs. Built for prepress workflows requiring ICC color management, CMYK separation inspection, and layer visibility control.

## Target Users

- DTP operators checking output quality
- QC professionals verifying PDF differences between revisions

## Key Requirements

- macOS-only (forever), optimized for Apple Silicon
- Primary workflow: inspect single PDF (separations, layers, metadata, color profiles)
- Secondary workflow: compare two PDFs (pixel overlay + structural diff)
- Batch: drag folder of 2-10 PDFs, generate comparisons
- Full ICC color management (spot colors, CMYK separations, overprint preview)
- Exportable reports (PDF/HTML) plus interactive on-screen viewing
- Well testable: unit + integration tests, 90% of tests in Rust

## Architecture

**SwiftUI shell + Rust PDF core**, bridged via UniFFI (proc-macros).

```
SwiftUI App Layer
  Views → ViewModels (@Observable, MVVM)
    → Swift Service Layer (PDFServiceProtocol)
      → UniFFI Bridge
        → Rust Core Library
          → PDF Engine (MuPDF via trait abstraction)
          → Diff Engine (pixel + structural)
          → Metadata Extractor (ICC, layers, separations)
          → Report Generator (PDF/HTML)
```

**Key architectural decisions:**

1. **MVVM with `@Observable`** — simple, testable, aligns with Apple patterns.
2. **All PDF processing in Rust** — Swift never touches PDF internals.
3. **UniFFI with proc-macros** — generates Swift bindings from annotated Rust code.
4. **Sync Rust functions + Swift `Task.detached`** — simpler than Rust async.
5. **PDF engine behind a Rust trait** — allows swapping MuPDF for PDFium later.
6. **MuPDF** as the PDF engine (AGPL or commercial license — decision deferred).

## Rust Core API Surface

### Documents

```rust
#[derive(uniffi::Object)]
pub struct PdfDocument { /* internal MuPDF handle */ }

impl PdfDocument {
    fn open(path: String) -> Result<Arc<Self>, PdfError>;
    fn page_count(&self) -> u32;
    fn render_page(&self, page: u32, dpi: u32, colorspace: RenderColorspace) -> Result<RenderedPage, PdfError>;
    fn metadata(&self) -> Result<DocumentMetadata, PdfError>;
    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError>;
    fn layers(&self) -> Result<Vec<Layer>, PdfError>;
    fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError>;
    fn render_separation(&self, page: u32, separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError>;
}
```

### Diff Engine

```rust
fn compute_pixel_diff(left: &PdfDocument, right: &PdfDocument, page: u32, dpi: u32, sensitivity: f32) -> Result<DiffResult, PdfError>;
fn compute_structural_diff(left: &PdfDocument, right: &PdfDocument) -> Result<StructuralDiffResult, PdfError>;
```

### Data Types

```rust
struct RenderedPage { bitmap: Vec<u8>, width: u32, height: u32, colorspace: RenderColorspace }
struct DocumentMetadata { title, author, creator, producer, creation_date, modification_date, pdf_version, page_count, file_size_bytes, is_linearized, is_encrypted, color_profiles }
struct PageMetadata { page_number, width_pt, height_pt, rotation, has_transparency, colorspaces_used, font_names, image_count }
struct Layer { name: String, is_visible: bool, layer_type: LayerType }
struct Separation { name: String, colorspace: String }
struct DiffResult { similarity_score, diff_bitmap, width, height, changed_regions, changed_pixel_count, total_pixel_count }
struct DiffRegion { x, y, width, height }
struct StructuralDiffResult { metadata_changes, text_changes, font_changes, page_size_changes }
enum RenderColorspace { Rgb, Cmyk }
enum ReportFormat { Pdf, Html }
```

### Report Generation

```rust
fn generate_report(left_path: String, right_path: String, diff: &DiffResult, structural: &StructuralDiffResult, format: ReportFormat, output_path: String) -> Result<(), PdfError>;
```

## SwiftUI App Structure

### Navigation Model

Single-window app with collapsible sidebar (`NavigationSplitView`). Sidebar shows document list and comparison pairs. Main content area switches between inspection and comparison modes.

### Views & ViewModels

| View | ViewModel | Responsibility |
|------|-----------|----------------|
| `AppView` | `AppViewModel` | Window management, document list, drag-drop handling |
| `InspectorView` | `InspectorViewModel` | Single PDF inspection, page navigation, zoom |
| `CompareView` | `CompareViewModel` | Diff display, mode switching, sensitivity control |
| `SeparationsView` | `SeparationsViewModel` | Color separation channel display, toggle plates |
| `MetadataPanel` | `MetadataPanelViewModel` | Document info, fonts, images, color profiles |
| `BatchView` | `BatchViewModel` | Folder comparison results, progress tracking |
| `PageRenderer` | (shared component) | Zoomable/pannable bitmap display |

### Compare Modes

- **Side-by-side** — two panels, synced zoom/pan
- **Overlay** — differences highlighted in red/green on single view
- **Swipe** — drag divider left/right to reveal differences
- **Onion skin** — adjustable opacity blend

### Drag-and-Drop Flow

1. User drops PDFs or folder onto sidebar / main drop zone
2. `AppViewModel.handleDrop()` validates (`.pdf`, max 10 files)
3. Files added to document list
4. 2 files dropped → auto-enter compare mode
5. Folder dropped → scan for PDFs (up to 10), show batch option

## Project Structure

```
pdf-diff-desktop/
├── Makefile
├── rust-core/
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── engine/    (traits.rs, mupdf_engine.rs, rendering.rs, icc.rs)
│       ├── diff/      (pixel.rs, structural.rs)
│       ├── metadata/  (extractor.rs, layers.rs, separations.rs)
│       ├── report/    (pdf_report.rs, html_report.rs)
│       └── error.rs
├── PdfDiffApp/
│   ├── PdfDiffApp.xcodeproj
│   ├── PdfDiff/
│   │   ├── ViewModels/
│   │   ├── Views/ (Sidebar/, Inspector/, Compare/, Batch/, Shared/)
│   │   └── Services/ (PDFServiceProtocol, PDFService, MockPDFService)
│   ├── PdfDiffTests/          (Swift Testing — ViewModels, bridge integration)
│   ├── PdfDiffSnapshotTests/  (swift-snapshot-testing)
│   └── PdfDiffUITests/        (XCUITest E2E)
├── generated/                  (UniFFI output — gitignored)
└── fixtures/                   (shared test PDFs)
```

## Build System

Makefile orchestrates: `cargo build` → `uniffi-bindgen generate` → `xcodebuild -create-xcframework` → `xcodebuild build`. Xcode Run Script phase triggers the Makefile.

## Error Handling

Single `PdfError` enum in Rust maps to Swift `throws`:

- `FileNotFound`, `InvalidPdf`, `PasswordProtected`, `PageOutOfRange`
- `RenderingFailed`, `UnsupportedColorspace`
- `DiffPageCountMismatch`, `DiffPageSizeMismatch`
- `ReportGenerationFailed`, `InternalError`

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Password-protected PDF | Error message (v1 — no password dialog) |
| Different page counts in diff | Compare shorter count, show warning |
| Different page sizes | Align top-left, flag in structural diff |
| Large PDFs (100+ pages) | Render on demand (visible page + 1 ahead) |
| Folder >10 PDFs | Accept first 10 alphabetically, show notice |
| Non-PDF dropped | Silently ignored (UTType filter) |
| Memory pressure | Cap at 300 DPI, LRU cache capped at ~500MB |

## Performance

| Operation | Target | Approach |
|-----------|--------|----------|
| Open PDF | <100ms | MuPDF lazy parsing |
| Render 150 DPI | <200ms | Background thread, placeholder shown |
| Render 300 DPI | <500ms | On demand only |
| Pixel diff (1 page) | <300ms | RGBA buffer comparison |
| Structural diff | <500ms | Text extraction + metadata |
| Metadata extraction | <50ms | PDF structure only |

### Caching

- **LRU page cache** (~500MB cap) keyed by document + page + DPI
- **Diff result cache** per page pair, invalidated on sensitivity change
- No disk cache — re-rendering is fast enough

### Batch Processing

Sequential pair processing (one at a time) to limit memory. Progressive UI — results appear as pairs complete.

## Testing Strategy

| Layer | Framework | Scope |
|-------|-----------|-------|
| Rust core | `cargo test` | PDF rendering, diff algorithms, metadata, ICC, reports |
| UniFFI bridge | Swift Testing | Type mapping, error propagation, round-trip |
| ViewModels | Swift Testing + MockPDFService | State transitions, business logic |
| Views | swift-snapshot-testing | Visual regression |
| E2E flows | XCUITest | Drag-drop, compare workflow, export |

90% of tests in Rust, 10% in Swift.

## Technology Stack Summary

| Component | Technology | License |
|-----------|------------|---------|
| App shell | SwiftUI (macOS 14+) | Apple |
| PDF engine | MuPDF 1.27+ via `mupdf` crate | AGPL or Commercial (TBD) |
| Rust-Swift bridge | UniFFI 0.29+ (proc-macros) | MPL-2.0 |
| Color management | MuPDF built-in ICC + `mupdf-sys` wrappers | (part of MuPDF) |
| Build | Makefile + Cargo + xcodebuild | — |
| Unit tests (Rust) | `cargo test` | — |
| Unit tests (Swift) | Swift Testing framework | Apple |
| Snapshot tests | swift-snapshot-testing | MIT |
| E2E tests | XCUITest | Apple |
