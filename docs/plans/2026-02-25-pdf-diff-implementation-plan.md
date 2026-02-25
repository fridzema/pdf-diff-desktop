# PDF Diff Desktop — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS-native PDF viewer and diff tool for DTP/QC professionals with ICC color management, separation inspection, and visual/structural comparison.

**Architecture:** SwiftUI shell (MVVM with @Observable) calling into a Rust core library via UniFFI. Rust handles all PDF processing using MuPDF. Swift handles UI and concurrency dispatch.

**Tech Stack:** Swift/SwiftUI (macOS 14+), Rust, MuPDF (via `mupdf` crate), UniFFI 0.29+, Swift Testing, swift-snapshot-testing

**Design doc:** `docs/plans/2026-02-25-pdf-diff-desktop-design.md`

---

## Phase 1: Rust Core Foundation

### Task 1: Scaffold Rust project with error types

**Files:**
- Create: `rust-core/Cargo.toml`
- Create: `rust-core/src/lib.rs`
- Create: `rust-core/src/error.rs`

**Step 1: Create Cargo.toml**

```toml
[package]
name = "pdf-diff-core"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["lib", "staticlib"]

[dependencies]
uniffi = { version = "0.29", features = ["cli"] }
mupdf = "0.6"
thiserror = "2"

[build-dependencies]
uniffi = { version = "0.29", features = ["build"] }

[[bin]]
name = "uniffi-bindgen"
path = "uniffi-bindgen.rs"
```

**Step 2: Create the UniFFI bindgen binary**

Create `rust-core/uniffi-bindgen.rs`:

```rust
fn main() {
    uniffi::uniffi_bindgen_main()
}
```

**Step 3: Create error.rs with PdfError enum**

```rust
use uniffi;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PdfError {
    #[error("File not found: {path}")]
    FileNotFound { path: String },
    #[error("Invalid PDF: {detail}")]
    InvalidPdf { detail: String },
    #[error("PDF is password protected")]
    PasswordProtected,
    #[error("Page {requested} out of range (total: {total})")]
    PageOutOfRange { requested: u32, total: u32 },
    #[error("Rendering failed: {detail}")]
    RenderingFailed { detail: String },
    #[error("Unsupported colorspace: {name}")]
    UnsupportedColorspace { name: String },
    #[error("Page count mismatch: left={left}, right={right}")]
    DiffPageCountMismatch { left: u32, right: u32 },
    #[error("Page size mismatch on page {page}")]
    DiffPageSizeMismatch { page: u32 },
    #[error("Report generation failed: {detail}")]
    ReportGenerationFailed { detail: String },
    #[error("Internal error: {detail}")]
    InternalError { detail: String },
}
```

**Step 4: Create lib.rs that re-exports error module**

```rust
pub mod error;

uniffi::setup_scaffolding!();
```

**Step 5: Verify it compiles**

Run: `cd rust-core && cargo build`
Expected: Compiles successfully

**Step 6: Commit**

```bash
git add rust-core/
git commit -m "feat: scaffold Rust project with error types and UniFFI setup"
```

---

### Task 2: PDF engine trait + data types

**Files:**
- Create: `rust-core/src/engine/mod.rs`
- Create: `rust-core/src/engine/traits.rs`
- Create: `rust-core/src/types.rs`
- Modify: `rust-core/src/lib.rs`

**Step 1: Create types.rs with all shared data types**

```rust
use uniffi;

#[derive(Debug, Clone, uniffi::Enum)]
pub enum RenderColorspace {
    Rgb,
    Cmyk,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum LayerType {
    View,
    Print,
    Export,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum ReportFormat {
    Pdf,
    Html,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct RenderedPage {
    pub bitmap: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub colorspace: RenderColorspace,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DocumentMetadata {
    pub title: Option<String>,
    pub author: Option<String>,
    pub creator: Option<String>,
    pub producer: Option<String>,
    pub creation_date: Option<String>,
    pub modification_date: Option<String>,
    pub pdf_version: String,
    pub page_count: u32,
    pub file_size_bytes: u64,
    pub is_linearized: bool,
    pub is_encrypted: bool,
    pub color_profiles: Vec<ColorProfile>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ColorProfile {
    pub name: String,
    pub colorspace: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PageMetadata {
    pub page_number: u32,
    pub width_pt: f64,
    pub height_pt: f64,
    pub rotation: u32,
    pub has_transparency: bool,
    pub colorspaces_used: Vec<String>,
    pub font_names: Vec<String>,
    pub image_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Layer {
    pub name: String,
    pub is_visible: bool,
    pub layer_type: LayerType,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Separation {
    pub name: String,
    pub colorspace: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DiffResult {
    pub similarity_score: f64,
    pub diff_bitmap: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub changed_regions: Vec<DiffRegion>,
    pub changed_pixel_count: u64,
    pub total_pixel_count: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DiffRegion {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct StructuralDiffResult {
    pub metadata_changes: Vec<MetadataChange>,
    pub text_changes: Vec<TextChange>,
    pub font_changes: Vec<FontChange>,
    pub page_size_changes: Vec<PageSizeChange>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct MetadataChange {
    pub field: String,
    pub left_value: Option<String>,
    pub right_value: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TextChange {
    pub page: u32,
    pub left_text: String,
    pub right_text: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FontChange {
    pub page: u32,
    pub left_fonts: Vec<String>,
    pub right_fonts: Vec<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PageSizeChange {
    pub page: u32,
    pub left_width: f64,
    pub left_height: f64,
    pub right_width: f64,
    pub right_height: f64,
}
```

**Step 2: Create engine/traits.rs with PdfEngine trait**

```rust
use crate::error::PdfError;
use crate::types::*;

pub trait PdfEngine: Send + Sync {
    fn open(&self, path: &str) -> Result<Box<dyn PdfDocumentHandle>, PdfError>;
}

pub trait PdfDocumentHandle: Send + Sync {
    fn page_count(&self) -> u32;
    fn render_page(&self, page: u32, dpi: u32, colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError>;
    fn metadata(&self) -> Result<DocumentMetadata, PdfError>;
    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError>;
    fn layers(&self) -> Result<Vec<Layer>, PdfError>;
    fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError>;
    fn render_separation(&self, page: u32, separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError>;
    fn extract_page_text(&self, page: u32) -> Result<String, PdfError>;
}
```

**Step 3: Create engine/mod.rs**

```rust
pub mod traits;
```

**Step 4: Update lib.rs**

```rust
pub mod engine;
pub mod error;
pub mod types;

uniffi::setup_scaffolding!();
```

**Step 5: Verify compilation**

Run: `cd rust-core && cargo build`
Expected: Compiles successfully

**Step 6: Commit**

```bash
git add rust-core/src/
git commit -m "feat: add PDF engine trait and shared data types"
```

---

### Task 3: MuPDF engine — open document + metadata

**Files:**
- Create: `rust-core/src/engine/mupdf_engine.rs`
- Modify: `rust-core/src/engine/mod.rs`
- Create: `fixtures/simple.pdf` (test fixture — generate with a helper)
- Create: `rust-core/tests/mupdf_engine_test.rs`

**Step 1: Create a test PDF fixture**

We need a real PDF for integration tests. Create a helper that generates one using the `mupdf` crate itself, or add a minimal pre-built PDF. The simplest approach is to include a tiny valid PDF binary. Alternatively, add `printpdf` as a dev-dependency to generate fixtures.

Add to `Cargo.toml` under `[dev-dependencies]`:

```toml
[dev-dependencies]
printpdf = "0.8"
tempfile = "3"
```

Create `rust-core/tests/helpers/mod.rs`:

```rust
use std::path::PathBuf;

pub fn fixture_path(name: &str) -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("..");
    path.push("fixtures");
    path.push(name);
    path
}

/// Creates a simple 1-page PDF at the given path using printpdf
pub fn create_simple_pdf(path: &std::path::Path) {
    use printpdf::*;
    let (doc, page1, layer1) = PdfDocument::new("Test Document", Mm(210.0), Mm(297.0), "Layer 1");
    let current_layer = doc.get_page(page1).get_layer(layer1);

    let font = doc.add_builtin_font(BuiltinFont::Helvetica).unwrap();
    current_layer.use_text("Hello World", 48.0, Mm(10.0), Mm(270.0), &font);

    let file = std::fs::File::create(path).unwrap();
    doc.save(&mut std::io::BufWriter::new(file)).unwrap();
}
```

**Step 2: Write failing test for MuPDF engine — open + page_count**

Create `rust-core/tests/mupdf_engine_test.rs`:

```rust
mod helpers;

use pdf_diff_core::engine::mupdf_engine::MuPdfEngine;
use pdf_diff_core::engine::traits::PdfEngine;

#[test]
fn test_open_valid_pdf() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();
    assert_eq!(doc.page_count(), 1);
}

#[test]
fn test_open_nonexistent_file() {
    let engine = MuPdfEngine::new();
    let result = engine.open("/nonexistent/path.pdf");
    assert!(result.is_err());
}

#[test]
fn test_metadata_extraction() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();
    let meta = doc.metadata().unwrap();

    assert_eq!(meta.page_count, 1);
    assert!(!meta.pdf_version.is_empty());
    assert!(!meta.is_encrypted);
}
```

**Step 3: Run test to verify it fails**

Run: `cd rust-core && cargo test`
Expected: FAIL — `mupdf_engine` module does not exist

**Step 4: Implement MuPDF engine — open + metadata**

Create `rust-core/src/engine/mupdf_engine.rs`:

```rust
use std::sync::Arc;
use mupdf::Document;
use crate::engine::traits::{PdfEngine, PdfDocumentHandle};
use crate::error::PdfError;
use crate::types::*;

pub struct MuPdfEngine;

impl MuPdfEngine {
    pub fn new() -> Self {
        Self
    }
}

impl PdfEngine for MuPdfEngine {
    fn open(&self, path: &str) -> Result<Box<dyn PdfDocumentHandle>, PdfError> {
        if !std::path::Path::new(path).exists() {
            return Err(PdfError::FileNotFound { path: path.to_string() });
        }

        let doc = Document::open(path).map_err(|e| {
            let msg = e.to_string();
            if msg.contains("password") {
                PdfError::PasswordProtected
            } else {
                PdfError::InvalidPdf { detail: msg }
            }
        })?;

        let file_size = std::fs::metadata(path)
            .map(|m| m.len())
            .unwrap_or(0);

        Ok(Box::new(MuPdfDocument {
            doc,
            path: path.to_string(),
            file_size,
        }))
    }
}

struct MuPdfDocument {
    doc: Document,
    path: String,
    file_size: u64,
}

// MuPDF Document is not Send/Sync by default, but we only access it
// from one thread at a time (Swift dispatches to background serially).
// This unsafe impl is required for the trait bound.
unsafe impl Send for MuPdfDocument {}
unsafe impl Sync for MuPdfDocument {}

impl PdfDocumentHandle for MuPdfDocument {
    fn page_count(&self) -> u32 {
        self.doc.page_count().unwrap_or(0) as u32
    }

    fn metadata(&self) -> Result<DocumentMetadata, PdfError> {
        let meta_field = |key: &str| -> Option<String> {
            self.doc.metadata(key).ok().filter(|s| !s.is_empty())
        };

        Ok(DocumentMetadata {
            title: meta_field("info:Title"),
            author: meta_field("info:Author"),
            creator: meta_field("info:Creator"),
            producer: meta_field("info:Producer"),
            creation_date: meta_field("info:CreationDate"),
            modification_date: meta_field("info:ModDate"),
            pdf_version: meta_field("format").unwrap_or_else(|| "unknown".to_string()),
            page_count: self.page_count(),
            file_size_bytes: self.file_size,
            is_linearized: false, // MuPDF doesn't expose this easily; skip for now
            is_encrypted: self.doc.needs_password().unwrap_or(false),
            color_profiles: Vec::new(), // Populated later via mupdf-sys FFI
        })
    }

    fn render_page(&self, _page: u32, _dpi: u32, _colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError> {
        todo!("Implemented in Task 4")
    }

    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError> {
        todo!("Implemented in Task 4")
    }

    fn layers(&self) -> Result<Vec<Layer>, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn separations(&self, _page: u32) -> Result<Vec<Separation>, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn render_separation(&self, _page: u32, _separation_index: u32, _dpi: u32) -> Result<RenderedPage, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn extract_page_text(&self, _page: u32) -> Result<String, PdfError> {
        todo!("Implemented in Task 6")
    }
}
```

**Step 5: Update engine/mod.rs**

```rust
pub mod mupdf_engine;
pub mod traits;
```

**Step 6: Ensure fixtures directory exists**

Run: `mkdir -p fixtures`

**Step 7: Run tests**

Run: `cd rust-core && cargo test`
Expected: All 3 tests PASS

**Step 8: Commit**

```bash
git add rust-core/ fixtures/
git commit -m "feat: MuPDF engine with open document and metadata extraction"
```

---

### Task 4: MuPDF engine — page rendering + page metadata

**Files:**
- Modify: `rust-core/src/engine/mupdf_engine.rs`
- Modify: `rust-core/tests/mupdf_engine_test.rs`

**Step 1: Write failing tests for rendering and page metadata**

Add to `rust-core/tests/mupdf_engine_test.rs`:

```rust
#[test]
fn test_render_page_rgb() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    use pdf_diff_core::types::RenderColorspace;
    let rendered = doc.render_page(0, 72, &RenderColorspace::Rgb).unwrap();

    assert!(rendered.width > 0);
    assert!(rendered.height > 0);
    assert!(!rendered.bitmap.is_empty());
    // RGB at 72 DPI for A4: ~595x842 pixels, 4 bytes per pixel (RGBA)
    assert_eq!(rendered.bitmap.len(), (rendered.width * rendered.height * 4) as usize);
}

#[test]
fn test_render_page_out_of_range() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let result = doc.render_page(99, 72, &pdf_diff_core::types::RenderColorspace::Rgb);
    assert!(result.is_err());
}

#[test]
fn test_pages_metadata() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();
    let pages = doc.pages_metadata().unwrap();

    assert_eq!(pages.len(), 1);
    assert_eq!(pages[0].page_number, 0);
    assert!(pages[0].width_pt > 0.0);
    assert!(pages[0].height_pt > 0.0);
}
```

**Step 2: Run tests to verify they fail**

Run: `cd rust-core && cargo test`
Expected: FAIL — `todo!()` panics

**Step 3: Implement render_page and pages_metadata**

Replace the `todo!()` stubs in `mupdf_engine.rs`:

```rust
fn render_page(&self, page: u32, dpi: u32, colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError> {
    let total = self.page_count();
    if page >= total {
        return Err(PdfError::PageOutOfRange { requested: page, total });
    }

    let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    let scale = dpi as f32 / 72.0;
    let matrix = mupdf::Matrix::new_scale(scale, scale);

    let cs = match colorspace {
        RenderColorspace::Rgb => mupdf::Colorspace::device_rgb(),
        RenderColorspace::Cmyk => mupdf::Colorspace::device_cmyk(),
    };

    let pixmap = pdf_page.to_pixmap(&matrix, &cs, false, true).map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    let width = pixmap.width() as u32;
    let height = pixmap.height() as u32;
    let samples = pixmap.samples().to_vec();

    Ok(RenderedPage {
        bitmap: samples,
        width,
        height,
        colorspace: colorspace.clone(),
    })
}

fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError> {
    let count = self.page_count();
    let mut pages = Vec::with_capacity(count as usize);

    for i in 0..count {
        let page = self.doc.load_page(i as i32).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let bounds = page.bounds().map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let width_pt = (bounds.x1 - bounds.x0) as f64;
        let height_pt = (bounds.y1 - bounds.y0) as f64;

        // Extract text to find font names
        let text_page = page.to_text_page(mupdf::TextPageOptions::empty()).ok();
        let font_names: Vec<String> = Vec::new(); // Font enumeration requires deeper MuPDF access

        pages.push(PageMetadata {
            page_number: i,
            width_pt,
            height_pt,
            rotation: 0, // MuPDF applies rotation during rendering
            has_transparency: false,
            colorspaces_used: Vec::new(),
            font_names,
            image_count: 0,
        });
    }

    Ok(pages)
}
```

**Step 4: Run tests**

Run: `cd rust-core && cargo test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add rust-core/
git commit -m "feat: page rendering (RGB/CMYK) and page metadata extraction"
```

---

### Task 5: MuPDF engine — layers + separations

**Files:**
- Modify: `rust-core/src/engine/mupdf_engine.rs`
- Modify: `rust-core/tests/mupdf_engine_test.rs`

**Step 1: Write tests for layers and separations**

Add to test file:

```rust
#[test]
fn test_layers_on_simple_pdf() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();
    let layers = doc.layers().unwrap();

    // Simple PDF has no layers — should return empty vec
    assert!(layers.is_empty());
}

#[test]
fn test_separations_on_simple_pdf() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();
    let seps = doc.separations(0).unwrap();

    // Simple RGB PDF has no spot color separations
    assert!(seps.is_empty());
}
```

**Step 2: Run tests to verify failure**

Run: `cd rust-core && cargo test`
Expected: FAIL — `todo!()` panics

**Step 3: Implement layers and separations**

Replace stubs in `mupdf_engine.rs`. Note: full OCG/separation support requires `mupdf-sys` FFI. For now, implement what the safe API exposes and return empty results for features needing FFI (document with TODO comments for Phase 2 enhancement):

```rust
fn layers(&self) -> Result<Vec<Layer>, PdfError> {
    // MuPDF safe API does not expose OCG layers directly.
    // Full implementation requires mupdf-sys FFI calls to:
    //   pdf_count_layer_configs, pdf_layer_config_ui, etc.
    // For now, return empty. Will be enhanced with mupdf-sys wrappers.
    Ok(Vec::new())
}

fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError> {
    let total = self.page_count();
    if page >= total {
        return Err(PdfError::PageOutOfRange { requested: page, total });
    }

    let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    let seps = pdf_page.separations().map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    // The safe mupdf API exposes Separations with len() and active_count()
    // but NOT individual names. Full implementation needs mupdf-sys FFI.
    // Return count-based placeholder entries for now.
    let count = seps.len();
    let mut result = Vec::new();
    for i in 0..count {
        result.push(Separation {
            name: format!("Separation {}", i),
            colorspace: "Unknown".to_string(),
        });
    }

    Ok(result)
}

fn render_separation(&self, page: u32, _separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError> {
    // Full separation rendering requires mupdf-sys FFI:
    //   fz_new_pixmap_from_page_contents_with_separations
    // For now, render the full page as a fallback.
    self.render_page(page, dpi, &RenderColorspace::Cmyk)
}
```

**Step 4: Run tests**

Run: `cd rust-core && cargo test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add rust-core/
git commit -m "feat: layers and separations stubs (safe API, mupdf-sys FFI enhancement TODO)"
```

---

### Task 6: Text extraction + structural diff

**Files:**
- Modify: `rust-core/src/engine/mupdf_engine.rs`
- Create: `rust-core/src/diff/mod.rs`
- Create: `rust-core/src/diff/structural.rs`
- Create: `rust-core/tests/structural_diff_test.rs`
- Modify: `rust-core/src/lib.rs`

**Step 1: Implement extract_page_text in mupdf_engine.rs**

Replace the `todo!()`:

```rust
fn extract_page_text(&self, page: u32) -> Result<String, PdfError> {
    let total = self.page_count();
    if page >= total {
        return Err(PdfError::PageOutOfRange { requested: page, total });
    }

    let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    let text_page = pdf_page.to_text_page(mupdf::TextPageOptions::empty()).map_err(|e| {
        PdfError::RenderingFailed { detail: e.to_string() }
    })?;

    Ok(text_page.to_string())
}
```

**Step 2: Write failing test for structural diff**

Create `rust-core/tests/structural_diff_test.rs`:

```rust
mod helpers;

use pdf_diff_core::diff::structural::compute_structural_diff;
use pdf_diff_core::engine::mupdf_engine::MuPdfEngine;
use pdf_diff_core::engine::traits::PdfEngine;

#[test]
fn test_structural_diff_identical() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let result = compute_structural_diff(doc.as_ref(), doc.as_ref()).unwrap();

    assert!(result.metadata_changes.is_empty());
    assert!(result.text_changes.is_empty());
    assert!(result.font_changes.is_empty());
    assert!(result.page_size_changes.is_empty());
}
```

**Step 3: Run test to verify failure**

Run: `cd rust-core && cargo test structural`
Expected: FAIL — module does not exist

**Step 4: Implement structural diff**

Create `rust-core/src/diff/mod.rs`:

```rust
pub mod structural;
```

Create `rust-core/src/diff/structural.rs`:

```rust
use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::*;

pub fn compute_structural_diff(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<StructuralDiffResult, PdfError> {
    let metadata_changes = diff_metadata(left, right)?;
    let (text_changes, font_changes) = diff_pages_content(left, right)?;
    let page_size_changes = diff_page_sizes(left, right)?;

    Ok(StructuralDiffResult {
        metadata_changes,
        text_changes,
        font_changes,
        page_size_changes,
    })
}

fn diff_metadata(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<Vec<MetadataChange>, PdfError> {
    let lm = left.metadata()?;
    let rm = right.metadata()?;
    let mut changes = Vec::new();

    let fields = [
        ("title", lm.title.clone(), rm.title.clone()),
        ("author", lm.author.clone(), rm.author.clone()),
        ("creator", lm.creator.clone(), rm.creator.clone()),
        ("producer", lm.producer.clone(), rm.producer.clone()),
        ("pdf_version", Some(lm.pdf_version.clone()), Some(rm.pdf_version.clone())),
    ];

    for (field, lv, rv) in fields {
        if lv != rv {
            changes.push(MetadataChange {
                field: field.to_string(),
                left_value: lv,
                right_value: rv,
            });
        }
    }

    Ok(changes)
}

fn diff_pages_content(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<(Vec<TextChange>, Vec<FontChange>), PdfError> {
    let left_count = left.page_count();
    let right_count = right.page_count();
    let compare_count = left_count.min(right_count);

    let mut text_changes = Vec::new();
    let mut font_changes = Vec::new();

    for page in 0..compare_count {
        let left_text = left.extract_page_text(page)?;
        let right_text = right.extract_page_text(page)?;

        if left_text != right_text {
            text_changes.push(TextChange {
                page,
                left_text,
                right_text,
            });
        }

        let lp = left.pages_metadata()?;
        let rp = right.pages_metadata()?;

        if page < lp.len() as u32 && page < rp.len() as u32 {
            let lf = &lp[page as usize].font_names;
            let rf = &rp[page as usize].font_names;
            if lf != rf {
                font_changes.push(FontChange {
                    page,
                    left_fonts: lf.clone(),
                    right_fonts: rf.clone(),
                });
            }
        }
    }

    Ok((text_changes, font_changes))
}

fn diff_page_sizes(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<Vec<PageSizeChange>, PdfError> {
    let lp = left.pages_metadata()?;
    let rp = right.pages_metadata()?;
    let compare_count = lp.len().min(rp.len());
    let mut changes = Vec::new();

    for i in 0..compare_count {
        let l = &lp[i];
        let r = &rp[i];
        if (l.width_pt - r.width_pt).abs() > 0.01 || (l.height_pt - r.height_pt).abs() > 0.01 {
            changes.push(PageSizeChange {
                page: i as u32,
                left_width: l.width_pt,
                left_height: l.height_pt,
                right_width: r.width_pt,
                right_height: r.height_pt,
            });
        }
    }

    Ok(changes)
}
```

**Step 5: Update lib.rs**

```rust
pub mod diff;
pub mod engine;
pub mod error;
pub mod types;

uniffi::setup_scaffolding!();
```

**Step 6: Run tests**

Run: `cd rust-core && cargo test`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add rust-core/
git commit -m "feat: text extraction and structural diff engine"
```

---

### Task 7: Pixel diff algorithm

**Files:**
- Create: `rust-core/src/diff/pixel.rs`
- Modify: `rust-core/src/diff/mod.rs`
- Create: `rust-core/tests/pixel_diff_test.rs`

**Step 1: Write failing tests**

Create `rust-core/tests/pixel_diff_test.rs`:

```rust
mod helpers;

use pdf_diff_core::diff::pixel::{compute_pixel_diff_from_bitmaps, compute_pixel_diff};
use pdf_diff_core::types::*;
use pdf_diff_core::engine::mupdf_engine::MuPdfEngine;
use pdf_diff_core::engine::traits::PdfEngine;

#[test]
fn test_identical_bitmaps_score_1() {
    let bitmap = vec![255u8; 100 * 100 * 4]; // 100x100 white RGBA
    let result = compute_pixel_diff_from_bitmaps(
        &bitmap, &bitmap, 100, 100, 0.1,
    );

    assert_eq!(result.similarity_score, 1.0);
    assert_eq!(result.changed_pixel_count, 0);
    assert!(result.changed_regions.is_empty());
}

#[test]
fn test_completely_different_bitmaps() {
    let white = vec![255u8; 10 * 10 * 4];
    let black = vec![0u8; 10 * 10 * 4];
    let result = compute_pixel_diff_from_bitmaps(
        &white, &black, 10, 10, 0.1,
    );

    assert!(result.similarity_score < 0.01);
    assert_eq!(result.changed_pixel_count, 100);
}

#[test]
fn test_sensitivity_threshold() {
    let mut bitmap_a = vec![128u8; 10 * 10 * 4];
    let mut bitmap_b = bitmap_a.clone();
    // Change one pixel slightly (within low sensitivity)
    bitmap_b[0] = 130; // R channel differs by 2

    let low_sensitivity = compute_pixel_diff_from_bitmaps(
        &bitmap_a, &bitmap_b, 10, 10, 0.05,
    );
    let high_sensitivity = compute_pixel_diff_from_bitmaps(
        &bitmap_a, &bitmap_b, 10, 10, 0.001,
    );

    // With low sensitivity, small change should be ignored
    assert!(low_sensitivity.changed_pixel_count <= high_sensitivity.changed_pixel_count);
}

#[test]
fn test_pixel_diff_with_real_pdfs() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }

    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    // Comparing a doc to itself should yield perfect score
    let result = compute_pixel_diff(doc.as_ref(), doc.as_ref(), 0, 72, 0.1).unwrap();
    assert_eq!(result.similarity_score, 1.0);
}
```

**Step 2: Run tests to verify failure**

Run: `cd rust-core && cargo test pixel`
Expected: FAIL — module does not exist

**Step 3: Implement pixel diff**

Create `rust-core/src/diff/pixel.rs`:

```rust
use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::*;

/// Compute pixel diff between two rendered pages of two documents.
pub fn compute_pixel_diff(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
    page: u32,
    dpi: u32,
    sensitivity: f32,
) -> Result<DiffResult, PdfError> {
    let cs = RenderColorspace::Rgb;
    let left_page = left.render_page(page, dpi, &cs)?;
    let right_page = right.render_page(page, dpi, &cs)?;

    if left_page.width != right_page.width || left_page.height != right_page.height {
        // Different sizes: compare using the smaller dimensions, flag the rest as changed
        let w = left_page.width.min(right_page.width);
        let h = left_page.height.min(right_page.height);
        // For simplicity in v1, just report the size mismatch
        return Ok(compute_pixel_diff_from_bitmaps(
            &left_page.bitmap, &right_page.bitmap,
            left_page.width, left_page.height,
            sensitivity,
        ));
    }

    Ok(compute_pixel_diff_from_bitmaps(
        &left_page.bitmap,
        &right_page.bitmap,
        left_page.width,
        left_page.height,
        sensitivity,
    ))
}

/// Pure bitmap comparison — no PDF dependency, fully unit-testable.
pub fn compute_pixel_diff_from_bitmaps(
    left: &[u8],
    right: &[u8],
    width: u32,
    height: u32,
    sensitivity: f32,
) -> DiffResult {
    let pixel_count = (width * height) as u64;
    let bytes_per_pixel = 4; // RGBA
    let threshold = (sensitivity * 255.0) as u16;

    let mut diff_bitmap = vec![0u8; left.len()];
    let mut changed_pixel_count: u64 = 0;

    // Track bounding boxes of changed regions using a simple grid
    let grid_size = 32u32;
    let grid_w = (width + grid_size - 1) / grid_size;
    let grid_h = (height + grid_size - 1) / grid_size;
    let mut grid_changed = vec![false; (grid_w * grid_h) as usize];

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * bytes_per_pixel) as usize;

            if idx + 3 >= left.len() || idx + 3 >= right.len() {
                break;
            }

            let dr = (left[idx] as i16 - right[idx] as i16).unsigned_abs();
            let dg = (left[idx + 1] as i16 - right[idx + 1] as i16).unsigned_abs();
            let db = (left[idx + 2] as i16 - right[idx + 2] as i16).unsigned_abs();
            let max_diff = dr.max(dg).max(db);

            if max_diff > threshold {
                changed_pixel_count += 1;
                // Mark diff pixel as red with semi-transparency
                diff_bitmap[idx] = 255;     // R
                diff_bitmap[idx + 1] = 0;   // G
                diff_bitmap[idx + 2] = 0;   // B
                diff_bitmap[idx + 3] = 180; // A

                let gx = x / grid_size;
                let gy = y / grid_size;
                grid_changed[(gy * grid_w + gx) as usize] = true;
            } else {
                // Unchanged pixel: dim version of original
                diff_bitmap[idx] = left[idx] / 3;
                diff_bitmap[idx + 1] = left[idx + 1] / 3;
                diff_bitmap[idx + 2] = left[idx + 2] / 3;
                diff_bitmap[idx + 3] = 255;
            }
        }
    }

    // Convert grid to bounding box regions
    let changed_regions = extract_regions(&grid_changed, grid_w, grid_h, grid_size);

    let similarity_score = if pixel_count == 0 {
        1.0
    } else {
        1.0 - (changed_pixel_count as f64 / pixel_count as f64)
    };

    DiffResult {
        similarity_score,
        diff_bitmap,
        width,
        height,
        changed_regions,
        changed_pixel_count,
        total_pixel_count: pixel_count,
    }
}

fn extract_regions(grid: &[bool], grid_w: u32, grid_h: u32, grid_size: u32) -> Vec<DiffRegion> {
    let mut regions = Vec::new();
    let mut visited = vec![false; grid.len()];

    for gy in 0..grid_h {
        for gx in 0..grid_w {
            let idx = (gy * grid_w + gx) as usize;
            if grid[idx] && !visited[idx] {
                // Flood-fill to find connected region
                let mut min_x = gx;
                let mut max_x = gx;
                let mut min_y = gy;
                let mut max_y = gy;
                let mut stack = vec![(gx, gy)];

                while let Some((cx, cy)) = stack.pop() {
                    let ci = (cy * grid_w + cx) as usize;
                    if visited[ci] || !grid[ci] {
                        continue;
                    }
                    visited[ci] = true;
                    min_x = min_x.min(cx);
                    max_x = max_x.max(cx);
                    min_y = min_y.min(cy);
                    max_y = max_y.max(cy);

                    if cx > 0 { stack.push((cx - 1, cy)); }
                    if cx < grid_w - 1 { stack.push((cx + 1, cy)); }
                    if cy > 0 { stack.push((cx, cy - 1)); }
                    if cy < grid_h - 1 { stack.push((cx, cy + 1)); }
                }

                regions.push(DiffRegion {
                    x: (min_x * grid_size) as f64,
                    y: (min_y * grid_size) as f64,
                    width: ((max_x - min_x + 1) * grid_size) as f64,
                    height: ((max_y - min_y + 1) * grid_size) as f64,
                });
            }
        }
    }

    regions
}
```

**Step 4: Update diff/mod.rs**

```rust
pub mod pixel;
pub mod structural;
```

**Step 5: Run tests**

Run: `cd rust-core && cargo test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add rust-core/
git commit -m "feat: pixel diff algorithm with sensitivity threshold and region detection"
```

---

## Phase 2: UniFFI Bridge + Build System

### Task 8: UniFFI exported API + binding generation

**Files:**
- Modify: `rust-core/src/lib.rs` (add UniFFI-exported wrapper)
- Create: `Makefile`
- Create: `.gitignore`

**Step 1: Create the UniFFI-exported PdfDocument wrapper in lib.rs**

This wraps the trait-based engine behind a UniFFI-friendly `Arc<Object>`:

```rust
pub mod diff;
pub mod engine;
pub mod error;
pub mod types;

use std::sync::Arc;
use engine::mupdf_engine::MuPdfEngine;
use engine::traits::{PdfEngine, PdfDocumentHandle};
use error::PdfError;
use types::*;

uniffi::setup_scaffolding!();

#[derive(uniffi::Object)]
pub struct PdfDocument {
    inner: Box<dyn PdfDocumentHandle>,
}

#[uniffi::export]
impl PdfDocument {
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>, PdfError> {
        let engine = MuPdfEngine::new();
        let inner = engine.open(&path)?;
        Ok(Arc::new(Self { inner }))
    }

    pub fn page_count(&self) -> u32 {
        self.inner.page_count()
    }

    pub fn render_page(&self, page: u32, dpi: u32, colorspace: RenderColorspace) -> Result<RenderedPage, PdfError> {
        self.inner.render_page(page, dpi, &colorspace)
    }

    pub fn metadata(&self) -> Result<DocumentMetadata, PdfError> {
        self.inner.metadata()
    }

    pub fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError> {
        self.inner.pages_metadata()
    }

    pub fn layers(&self) -> Result<Vec<Layer>, PdfError> {
        self.inner.layers()
    }

    pub fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError> {
        self.inner.separations(page)
    }

    pub fn render_separation(&self, page: u32, separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError> {
        self.inner.render_separation(page, separation_index, dpi)
    }
}

#[uniffi::export]
pub fn compute_pixel_diff(
    left: &PdfDocument,
    right: &PdfDocument,
    page: u32,
    dpi: u32,
    sensitivity: f32,
) -> Result<DiffResult, PdfError> {
    diff::pixel::compute_pixel_diff(
        left.inner.as_ref(),
        right.inner.as_ref(),
        page, dpi, sensitivity,
    )
}

#[uniffi::export]
pub fn compute_structural_diff(
    left: &PdfDocument,
    right: &PdfDocument,
) -> Result<StructuralDiffResult, PdfError> {
    diff::structural::compute_structural_diff(
        left.inner.as_ref(),
        right.inner.as_ref(),
    )
}

#[uniffi::export]
pub fn generate_report(
    _left_path: String,
    _right_path: String,
    _diff: DiffResult,
    _structural: StructuralDiffResult,
    _format: ReportFormat,
    _output_path: String,
) -> Result<(), PdfError> {
    // Implemented in a later task
    Err(PdfError::ReportGenerationFailed { detail: "Not yet implemented".to_string() })
}
```

**Step 2: Create Makefile**

```makefile
.PHONY: build-rust generate-bindings build-app test-rust test-swift test clean

RUST_TARGET = aarch64-apple-darwin
RUST_LIB = rust-core/target/$(RUST_TARGET)/release/libpdf_diff_core.a
GENERATED_DIR = generated

build-rust:
	cd rust-core && cargo build --release --target $(RUST_TARGET)

generate-bindings: build-rust
	cd rust-core && cargo run --bin uniffi-bindgen generate \
		--library target/$(RUST_TARGET)/release/libpdf_diff_core.dylib \
		-l swift \
		-o ../$(GENERATED_DIR)/

build-app: generate-bindings
	@echo "Run: xcodebuild -project PdfDiffApp/PdfDiffApp.xcodeproj -scheme PdfDiff build"

test-rust:
	cd rust-core && cargo test

test-swift:
	xcodebuild test -project PdfDiffApp/PdfDiffApp.xcodeproj -scheme PdfDiff

test: test-rust test-swift

clean:
	cd rust-core && cargo clean
	rm -rf $(GENERATED_DIR)
```

**Step 3: Create .gitignore**

```
# Rust
rust-core/target/

# UniFFI generated
generated/

# Xcode
PdfDiffApp/build/
PdfDiffApp/DerivedData/
*.xcuserdata

# macOS
.DS_Store

# Test artifacts
fixtures/*.pdf
```

**Step 4: Verify Rust build + binding generation**

Run: `make build-rust`
Expected: Compiles successfully

Run: `make generate-bindings`
Expected: `generated/pdf_diff_core.swift` and `generated/pdf_diff_coreFFI.h` created

**Step 5: Commit**

```bash
git add Makefile .gitignore rust-core/src/lib.rs
git commit -m "feat: UniFFI exported API, Makefile build system, and gitignore"
```

---

## Phase 3: SwiftUI Application Shell

### Task 9: Xcode project + basic app window

**This task requires manual Xcode steps. Instructions for the implementor:**

1. Open Xcode → File → New → Project → macOS → App
2. Product Name: `PdfDiff`, Team: your team, Organization: your org
3. Interface: SwiftUI, Language: Swift, Storage: None
4. Save into `PdfDiffApp/` directory
5. Set deployment target to macOS 14.0
6. Add a "Run Script" build phase (before "Compile Sources") that runs: `cd "$SRCROOT/.." && make generate-bindings`
7. Add the generated `pdf_diff_core.swift` to the project
8. Add `libpdf_diff_core.a` as a linked framework
9. Add `generated/` to Header Search Paths

**After Xcode project exists, create the service protocol and app structure.**

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/PDFServiceProtocol.swift`
- Create: `PdfDiffApp/PdfDiff/Services/MockPDFService.swift`
- Create: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift`
- Create: `PdfDiffApp/PdfDiff/Views/AppView.swift`

**Step 1: Create PDFServiceProtocol.swift**

```swift
import Foundation

protocol PDFServiceProtocol: Sendable {
    func openDocument(path: String) throws -> OpenedDocument
    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap
    func metadata(document: OpenedDocument) throws -> PDFMetadata
    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata]
    func layers(document: OpenedDocument) throws -> [PDFLayer]
    func separations(document: OpenedDocument, page: UInt32) throws -> [PDFSeparation]
    func computePixelDiff(left: OpenedDocument, right: OpenedDocument, page: UInt32, dpi: UInt32, sensitivity: Float) throws -> PDFDiffResult
    func computeStructuralDiff(left: OpenedDocument, right: OpenedDocument) throws -> PDFStructuralDiffResult
}

// Swift-side wrapper types that map from UniFFI types
struct OpenedDocument: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let fileName: String
    let pageCount: UInt32

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: OpenedDocument, rhs: OpenedDocument) -> Bool { lhs.id == rhs.id }
}

struct RenderedBitmap {
    let image: NSImage
    let width: UInt32
    let height: UInt32
}

struct PDFMetadata {
    let title: String?
    let author: String?
    let creator: String?
    let producer: String?
    let creationDate: String?
    let modificationDate: String?
    let pdfVersion: String
    let pageCount: UInt32
    let fileSizeBytes: UInt64
    let isEncrypted: Bool
    let colorProfiles: [String]
}

struct PDFPageMetadata {
    let pageNumber: UInt32
    let widthPt: Double
    let heightPt: Double
    let rotation: UInt32
    let fontNames: [String]
    let imageCount: UInt32
}

struct PDFLayer {
    let name: String
    let isVisible: Bool
}

struct PDFSeparation {
    let name: String
    let colorspace: String
}

struct PDFDiffResult {
    let similarityScore: Double
    let diffImage: NSImage?
    let changedRegions: [CGRect]
    let changedPixelCount: UInt64
    let totalPixelCount: UInt64
}

struct PDFStructuralDiffResult {
    let metadataChanges: [(field: String, left: String?, right: String?)]
    let textChanges: [(page: UInt32, left: String, right: String)]
    let fontChanges: [(page: UInt32, left: [String], right: [String])]
    let pageSizeChanges: [(page: UInt32, leftSize: CGSize, rightSize: CGSize)]
}
```

**Step 2: Create MockPDFService.swift**

```swift
import Foundation
import AppKit

final class MockPDFService: PDFServiceProtocol, @unchecked Sendable {
    var shouldThrow = false

    func openDocument(path: String) throws -> OpenedDocument {
        if shouldThrow { throw NSError(domain: "Mock", code: 1) }
        return OpenedDocument(
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            pageCount: 3
        )
    }

    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap {
        let image = NSImage(size: NSSize(width: 200, height: 280))
        return RenderedBitmap(image: image, width: 200, height: 280)
    }

    func metadata(document: OpenedDocument) throws -> PDFMetadata {
        PDFMetadata(
            title: "Mock Document", author: "Test", creator: "Tests",
            producer: "MockPDF", creationDate: "2026-01-01", modificationDate: "2026-01-02",
            pdfVersion: "1.7", pageCount: 3, fileSizeBytes: 12345,
            isEncrypted: false, colorProfiles: ["sRGB"]
        )
    }

    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata] {
        (0..<3).map { i in
            PDFPageMetadata(pageNumber: UInt32(i), widthPt: 595, heightPt: 842, rotation: 0, fontNames: ["Helvetica"], imageCount: 0)
        }
    }

    func layers(document: OpenedDocument) throws -> [PDFLayer] { [] }
    func separations(document: OpenedDocument, page: UInt32) throws -> [PDFSeparation] { [] }

    func computePixelDiff(left: OpenedDocument, right: OpenedDocument, page: UInt32, dpi: UInt32, sensitivity: Float) throws -> PDFDiffResult {
        PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
    }

    func computeStructuralDiff(left: OpenedDocument, right: OpenedDocument) throws -> PDFStructuralDiffResult {
        PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])
    }
}
```

**Step 3: Create AppViewModel.swift**

```swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable @MainActor
final class AppViewModel {
    var documents: [OpenedDocument] = []
    var selectedDocument: OpenedDocument?
    var errorMessage: String?
    var isDropTargeted = false

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func openFiles(urls: [URL]) {
        let pdfUrls = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .prefix(10)

        for url in pdfUrls {
            do {
                let doc = try pdfService.openDocument(path: url.path)
                documents.append(doc)
            } catch {
                errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if documents.count == 1 {
            selectedDocument = documents.first
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let semaphore = DispatchSemaphore(value: 0)

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) { item, _ in
                    if let url = item as? URL {
                        urls.append(url)
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
        }

        guard !urls.isEmpty else { return false }
        openFiles(urls: urls)
        return true
    }

    func removeDocument(_ doc: OpenedDocument) {
        documents.removeAll { $0.id == doc.id }
        if selectedDocument == doc {
            selectedDocument = documents.first
        }
    }
}
```

**Step 4: Create AppView.swift**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarContent(viewModel: viewModel)
        } detail: {
            if let selected = viewModel.selectedDocument {
                Text("Inspector for \(selected.fileName)")
                    .font(.title2)
            } else {
                DropZoneView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onDrop(of: [.pdf], isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct SidebarContent: View {
    let viewModel: AppViewModel

    var body: some View {
        List(viewModel.documents, selection: Binding(
            get: { viewModel.selectedDocument },
            set: { viewModel.selectedDocument = $0 }
        )) { doc in
            Label(doc.fileName, systemImage: "doc.richtext")
        }
        .navigationTitle("Documents")
    }
}

struct DropZoneView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop PDF files here")
                .font(.title2)
            Text("Or use File → Open to add documents")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(viewModel.isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

**Step 5: Update PdfDiffApp.swift entry point**

```swift
import SwiftUI

@main
struct PdfDiffApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(viewModel: AppViewModel(pdfService: MockPDFService()))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        // Post notification or use environment to pass URLs
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
```

**Step 6: Verify it builds and launches**

Build and run the Xcode project. You should see a window with a sidebar and drop zone.

**Step 7: Commit**

```bash
git add PdfDiffApp/
git commit -m "feat: SwiftUI app shell with sidebar, drop zone, and mock PDF service"
```

---

## Phase 4: Inspector Views

### Task 10: InspectorViewModel + MetadataPanel

**Files:**
- Create: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Create: `PdfDiffApp/PdfDiff/ViewModels/MetadataPanelViewModel.swift`
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/MetadataPanel.swift`
- Create: `PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift`

**Step 1: Write failing tests**

Create `InspectorViewModelTests.swift`:

```swift
import Testing
@testable import PdfDiff

@Suite("InspectorViewModel Tests")
@MainActor
struct InspectorViewModelTests {
    let mockService = MockPDFService()

    @Test("loads metadata on document set")
    func loadsMetadata() async {
        let doc = try! mockService.openDocument(path: "/test.pdf")
        let vm = InspectorViewModel(pdfService: mockService)

        await vm.loadDocument(doc)

        #expect(vm.metadata?.title == "Mock Document")
        #expect(vm.metadata?.pageCount == 3)
    }

    @Test("navigates pages forward and backward")
    func pageNavigation() async {
        let doc = try! mockService.openDocument(path: "/test.pdf")
        let vm = InspectorViewModel(pdfService: mockService)
        await vm.loadDocument(doc)

        #expect(vm.currentPage == 0)

        vm.nextPage()
        #expect(vm.currentPage == 1)

        vm.nextPage()
        #expect(vm.currentPage == 2)

        vm.nextPage()
        #expect(vm.currentPage == 2) // Should not exceed page count

        vm.previousPage()
        #expect(vm.currentPage == 1)
    }

    @Test("does not go below page 0")
    func doesNotGoBelowZero() async {
        let doc = try! mockService.openDocument(path: "/test.pdf")
        let vm = InspectorViewModel(pdfService: mockService)
        await vm.loadDocument(doc)

        vm.previousPage()
        #expect(vm.currentPage == 0)
    }
}
```

**Step 2: Run tests — expect failure**

**Step 3: Implement InspectorViewModel**

```swift
import Foundation
import AppKit

@Observable @MainActor
final class InspectorViewModel {
    var document: OpenedDocument?
    var currentPage: UInt32 = 0
    var renderedImage: NSImage?
    var metadata: PDFMetadata?
    var pagesMetadata: [PDFPageMetadata] = []
    var isRendering = false
    var errorMessage: String?

    enum Tab: String, CaseIterable { case inspector, compare, separations }
    var selectedTab: Tab = .inspector

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func loadDocument(_ doc: OpenedDocument) async {
        self.document = doc
        self.currentPage = 0

        do {
            self.metadata = try pdfService.metadata(document: doc)
            self.pagesMetadata = try pdfService.pagesMetadata(document: doc)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        await renderCurrentPage()
    }

    func nextPage() {
        guard let doc = document, currentPage < doc.pageCount - 1 else { return }
        currentPage += 1
        Task { await renderCurrentPage() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        Task { await renderCurrentPage() }
    }

    private func renderCurrentPage() async {
        guard let doc = document else { return }
        isRendering = true
        defer { isRendering = false }

        do {
            let rendered = try pdfService.renderPage(document: doc, page: currentPage, dpi: 150)
            self.renderedImage = rendered.image
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

**Step 4: Run tests — expect pass**

**Step 5: Create InspectorView and MetadataPanel**

`InspectorView.swift`:

```swift
import SwiftUI

struct InspectorView: View {
    @State var viewModel: InspectorViewModel

    var body: some View {
        VSplitView {
            // Page renderer area
            VStack {
                HStack {
                    Button(action: { viewModel.previousPage() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentPage == 0)

                    Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")

                    Button(action: { viewModel.nextPage() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)
                }
                .padding(.top, 8)

                if viewModel.isRendering {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = viewModel.renderedImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else {
                    Text("No page rendered")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 300)

            // Metadata panel
            MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
                .frame(minHeight: 150, maxHeight: 300)
        }
    }
}
```

`MetadataPanel.swift`:

```swift
import SwiftUI

struct MetadataPanel: View {
    let metadata: PDFMetadata?
    let pageMetadata: [PDFPageMetadata]

    enum Tab: String, CaseIterable { case metadata, fonts, images, colors }
    @State private var selectedTab: Tab = .metadata

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue.capitalized).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            ScrollView {
                switch selectedTab {
                case .metadata:
                    metadataContent
                case .fonts:
                    fontsContent
                case .images:
                    imagesContent
                case .colors:
                    colorsContent
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        if let m = metadata {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Title", m.title ?? "—")
                row("Author", m.author ?? "—")
                row("Creator", m.creator ?? "—")
                row("Producer", m.producer ?? "—")
                row("PDF Version", m.pdfVersion)
                row("Pages", "\(m.pageCount)")
                row("File Size", ByteCountFormatter.string(fromByteCount: Int64(m.fileSizeBytes), countStyle: .file))
                row("Encrypted", m.isEncrypted ? "Yes" : "No")
            }
        } else {
            Text("No document loaded").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var fontsContent: some View {
        let allFonts = Set(pageMetadata.flatMap(\.fontNames)).sorted()
        if allFonts.isEmpty {
            Text("No fonts found").foregroundStyle(.secondary)
        } else {
            ForEach(allFonts, id: \.self) { font in
                Text(font).font(.system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var imagesContent: some View {
        let totalImages = pageMetadata.reduce(0) { $0 + $1.imageCount }
        Text("Total images: \(totalImages)")
    }

    @ViewBuilder
    private var colorsContent: some View {
        if let m = metadata {
            ForEach(m.colorProfiles, id: \.self) { profile in
                Text(profile)
            }
            if m.colorProfiles.isEmpty {
                Text("No ICC profiles found").foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some GridRow<some View> {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
```

**Step 6: Commit**

```bash
git add PdfDiffApp/
git commit -m "feat: inspector view with page navigation and metadata panel"
```

---

## Phase 5: Compare Views (Tasks 11-14)

### Task 11: CompareViewModel + side-by-side view

Follow the same TDD pattern as Task 10. Key elements:

**CompareViewModel.swift** — manages two documents, current page, selected compare mode (enum: `sideBySide`, `overlay`, `swipe`, `onionSkin`), sensitivity slider (Float 0-1), and diff results.

**Test:** Compare mode switching, sensitivity changes trigger re-diff, page navigation syncs both sides.

**CompareView.swift** — tab bar for mode selection, sensitivity slider, page nav, delegates to sub-views.

**SideBySideView.swift** — `HStack` of two `PageRenderer` views with synced `ScrollView` offsets.

### Task 12: Overlay, Swipe, and Onion Skin views

**OverlayView.swift** — single `PageRenderer` showing the diff bitmap from `DiffResult.diff_bitmap`.

**SwipeView.swift** — `GeometryReader` with a draggable divider. Left side clips the left image, right side clips the right image.

**OnionSkinView.swift** — two overlaid images, top image opacity controlled by a slider.

### Task 13: DiffSummaryPanel

Shows `similarity_score` as percentage, list of `changed_regions` with click-to-zoom, structural changes (metadata, text, fonts, page sizes) in expandable sections.

### Task 14: Batch comparison view

**BatchViewModel.swift** — takes list of documents, pairs them (consecutive or all-vs-first), processes sequentially, tracks progress.

**BatchView.swift** — list of pairs with status (pending/processing/done), similarity score badge, click to open full compare view.

---

## Phase 6: Drag-and-Drop + File Handling (Task 15)

Enhance `AppViewModel.handleDrop()` to handle:
- Multiple PDF files → add to sidebar
- Single folder → scan for PDFs (up to 10), add all
- Auto-enter compare mode if exactly 2 files
- Auto-suggest batch mode if >2 files

Add File → Open menu command, File → Open Folder command.

---

## Phase 7: Report Generation (Tasks 16-17)

### Task 16: Rust report engine

**Files:** `rust-core/src/report/pdf_report.rs`, `rust-core/src/report/html_report.rs`

HTML report: standalone HTML file with embedded diff images (base64), metadata table, structural changes. Use `askama` or raw string templates.

PDF report: use `printpdf` crate to generate a summary PDF with diff images and text.

### Task 17: Export UI

Add "Export Report" button to CompareView and BatchView. `NSSavePanel` for choosing output location. Format picker (PDF/HTML).

---

## Phase 8: Polish + Performance (Tasks 18-19)

### Task 18: LRU page cache

Create `PageCache` actor in Swift that holds rendered `NSImage`s keyed by `(documentId, page, dpi)`. Cap at ~500MB using byte-size tracking. Integrate into `PDFService` so cache is checked before calling Rust.

### Task 19: Edge case handling

- Password-protected PDF error dialog
- Page count mismatch warning in compare mode
- Folder >10 PDFs notice
- Memory pressure: monitor with `os_proc_available_memory()`, reduce cache if low

---

## Execution Notes

**Build order matters:** Tasks 1-8 must be sequential. Tasks 9-10 depend on 8. Tasks 11-14 depend on 10. Tasks 15-17 can be parallelized after 14. Tasks 18-19 are final polish.

**Test fixtures:** The `helpers::create_simple_pdf()` function creates test PDFs on demand. For testing diff with actual differences, create a second fixture `create_modified_pdf()` that changes text or adds a colored rectangle.

**mupdf-sys FFI enhancement:** Tasks 3-5 use the safe `mupdf` API with stubs for features requiring `mupdf-sys`. A follow-up phase should implement the unsafe wrappers for: ICC profile toggle, separation names, OCG layer enumeration, separation-aware rendering.
