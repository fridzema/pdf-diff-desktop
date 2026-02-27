# v1.0 Feature Roadmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add preflight checks, barcode detection, separation preview, report generation, and batch comparison to make PDF Diff Desktop a competitive standalone prepress QC tool.

**Architecture:** Hybrid approach — Rust core handles rendering-based analysis (ink coverage, page consistency), Swift/PDFKit handles PDF structure inspection (page boxes, fonts). Both feed into a unified `PreflightResult` model. VisionKit handles barcode detection. Reports generated in Swift using PDFKit.

**Tech Stack:** Rust (MuPDF 0.6, UniFFI 0.29), Swift 5.10 (SwiftUI, PDFKit, Vision framework), macOS 14+

---

## Phase 1: Preflight Data Model + Rust Checks

### Task 1: Preflight Data Types (Rust)

**Files:**
- Create: `rust-core/src/preflight/mod.rs`
- Modify: `rust-core/src/types.rs`
- Modify: `rust-core/src/lib.rs`
- Test: `rust-core/tests/preflight_test.rs`

**Step 1: Add preflight types to `types.rs`**

Add after the existing `PageSizeChange` struct (after line 132):

```rust
// --- Preflight types ---

#[derive(Debug, Clone, uniffi::Enum)]
pub enum PreflightSeverity {
    Pass,
    Warn,
    Fail,
    Info,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum PreflightCategory {
    InkCoverage,
    PageConsistency,
    PageBoxes,
    Fonts,
    Images,
    ColorSpace,
    SpotColors,
    Transparency,
    Overprint,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PreflightCheck {
    pub category: PreflightCategory,
    pub severity: PreflightSeverity,
    pub title: String,
    pub detail: String,
    pub page: Option<u32>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PreflightSummary {
    pub pass_count: u32,
    pub warn_count: u32,
    pub fail_count: u32,
    pub info_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PreflightResult {
    pub checks: Vec<PreflightCheck>,
    pub summary: PreflightSummary,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct InkCoverageResult {
    pub page: u32,
    pub cyan: f64,
    pub magenta: f64,
    pub yellow: f64,
    pub black: f64,
    pub total: f64,
}
```

**Step 2: Create the preflight module**

Create `rust-core/src/preflight/mod.rs`:

```rust
pub mod ink_coverage;
pub mod page_checks;
```

Add to `rust-core/src/lib.rs` (after line 4):
```rust
pub mod preflight;
```

**Step 3: Commit**

```bash
git add rust-core/src/types.rs rust-core/src/preflight/ rust-core/src/lib.rs
git commit -m "feat: add preflight data types and module scaffold"
```

---

### Task 2: Ink Coverage Check (Rust)

Renders each page in CMYK and analyzes channel values to calculate ink coverage percentages. This is the highest-value preflight check that requires Rust rendering.

**Files:**
- Create: `rust-core/src/preflight/ink_coverage.rs`
- Test: `rust-core/tests/preflight_test.rs`

**Step 1: Write the failing test**

Create `rust-core/tests/preflight_test.rs`:

```rust
mod helpers;

use pdf_diff_core::engine::mupdf_engine::MuPdfEngine;
use pdf_diff_core::engine::traits::PdfEngine;
use pdf_diff_core::preflight::ink_coverage::compute_ink_coverage;

#[test]
fn test_ink_coverage_simple_pdf() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }
    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let result = compute_ink_coverage(doc.as_ref(), 0, 72).unwrap();
    assert_eq!(result.page, 0);
    // Simple PDF with black text on white: low C/M/Y, some K
    assert!(result.cyan < 5.0, "Cyan should be low: {}", result.cyan);
    assert!(result.magenta < 5.0, "Magenta should be low: {}", result.magenta);
    assert!(result.yellow < 5.0, "Yellow should be low: {}", result.yellow);
    assert!(result.total < 100.0, "Total should be under 100%: {}", result.total);
    assert!(result.total >= 0.0);
}

#[test]
fn test_ink_coverage_page_out_of_range() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }
    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let result = compute_ink_coverage(doc.as_ref(), 999, 72);
    assert!(result.is_err());
}
```

**Step 2: Run test to verify it fails**

Run: `cd rust-core && cargo test test_ink_coverage -- --nocapture`
Expected: FAIL — module not found

**Step 3: Implement ink coverage**

Create `rust-core/src/preflight/ink_coverage.rs`:

```rust
use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{InkCoverageResult, RenderColorspace};

/// Computes ink coverage for a page by rendering in CMYK and analyzing channel values.
/// Returns percentages (0-100) for each channel and total ink.
/// Uses low DPI (72) for speed — coverage percentages are resolution-independent.
pub fn compute_ink_coverage(
    doc: &dyn PdfDocumentHandle,
    page: u32,
    dpi: u32,
) -> Result<InkCoverageResult, PdfError> {
    let rendered = doc.render_page(page, dpi, &RenderColorspace::Cmyk)?;

    // CMYK pixmap: 5 bytes per pixel (C, M, Y, K, A)
    let bytes_per_pixel = 5;
    let pixel_count = (rendered.width * rendered.height) as usize;

    if rendered.bitmap.len() < pixel_count * bytes_per_pixel {
        return Err(PdfError::RenderingFailed {
            detail: "CMYK bitmap size mismatch".to_string(),
        });
    }

    let mut sum_c: f64 = 0.0;
    let mut sum_m: f64 = 0.0;
    let mut sum_y: f64 = 0.0;
    let mut sum_k: f64 = 0.0;
    let mut max_total: f64 = 0.0;

    for i in 0..pixel_count {
        let offset = i * bytes_per_pixel;
        let c = rendered.bitmap[offset] as f64 / 255.0 * 100.0;
        let m = rendered.bitmap[offset + 1] as f64 / 255.0 * 100.0;
        let y = rendered.bitmap[offset + 2] as f64 / 255.0 * 100.0;
        let k = rendered.bitmap[offset + 3] as f64 / 255.0 * 100.0;
        sum_c += c;
        sum_m += m;
        sum_y += y;
        sum_k += k;
        let total = c + m + y + k;
        if total > max_total {
            max_total = total;
        }
    }

    let n = pixel_count as f64;
    Ok(InkCoverageResult {
        page,
        cyan: sum_c / n,
        magenta: sum_m / n,
        yellow: sum_y / n,
        black: sum_k / n,
        total: max_total,
    })
}
```

**Note:** MuPDF CMYK pixmaps are 5 bytes per pixel (CMYKA). If this turns out to be 4 bytes (no alpha), adjust `bytes_per_pixel` to 4. Verify by checking `rendered.bitmap.len() / pixel_count` in the test.

**Step 4: Run test to verify it passes**

Run: `cd rust-core && cargo test test_ink_coverage -- --nocapture`
Expected: PASS (adjust bytes_per_pixel if the first run reveals the actual CMYK format)

**Step 5: Commit**

```bash
git add rust-core/src/preflight/ink_coverage.rs rust-core/tests/preflight_test.rs
git commit -m "feat: add ink coverage check via CMYK rendering analysis"
```

---

### Task 3: Page Consistency Check (Rust)

Checks that all pages have the same dimensions and orientation.

**Files:**
- Create: `rust-core/src/preflight/page_checks.rs`
- Modify: `rust-core/tests/preflight_test.rs`

**Step 1: Write the failing test**

Add to `rust-core/tests/preflight_test.rs`:

```rust
use pdf_diff_core::preflight::page_checks::check_page_consistency;
use pdf_diff_core::types::PreflightSeverity;

#[test]
fn test_page_consistency_single_page() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }
    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let checks = check_page_consistency(doc.as_ref()).unwrap();
    // Single-page doc: should pass
    assert!(checks.iter().all(|c| matches!(c.severity, PreflightSeverity::Pass)));
}
```

**Step 2: Run test to verify it fails**

Run: `cd rust-core && cargo test test_page_consistency -- --nocapture`
Expected: FAIL — function not found

**Step 3: Implement page consistency check**

Create `rust-core/src/preflight/page_checks.rs`:

```rust
use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{PreflightCheck, PreflightCategory, PreflightSeverity};

/// Checks that all pages have consistent dimensions and orientation.
pub fn check_page_consistency(
    doc: &dyn PdfDocumentHandle,
) -> Result<Vec<PreflightCheck>, PdfError> {
    let pages = doc.pages_metadata()?;
    let mut checks = Vec::new();

    if pages.is_empty() {
        checks.push(PreflightCheck {
            category: PreflightCategory::PageConsistency,
            severity: PreflightSeverity::Warn,
            title: "No pages".to_string(),
            detail: "Document has no pages".to_string(),
            page: None,
        });
        return Ok(checks);
    }

    let first = &pages[0];
    let ref_width = first.width_pt;
    let ref_height = first.height_pt;
    let ref_landscape = ref_width > ref_height;
    let mut all_consistent = true;

    for p in pages.iter().skip(1) {
        let size_match = (p.width_pt - ref_width).abs() < 0.5
            && (p.height_pt - ref_height).abs() < 0.5;
        let landscape = p.width_pt > p.height_pt;

        if !size_match {
            all_consistent = false;
            checks.push(PreflightCheck {
                category: PreflightCategory::PageConsistency,
                severity: PreflightSeverity::Warn,
                title: format!("Page {} size mismatch", p.page_number + 1),
                detail: format!(
                    "Page {} is {:.1} x {:.1} pt, expected {:.1} x {:.1} pt",
                    p.page_number + 1, p.width_pt, p.height_pt, ref_width, ref_height
                ),
                page: Some(p.page_number),
            });
        }

        if landscape != ref_landscape {
            all_consistent = false;
            checks.push(PreflightCheck {
                category: PreflightCategory::PageConsistency,
                severity: PreflightSeverity::Warn,
                title: format!("Page {} orientation mismatch", p.page_number + 1),
                detail: format!(
                    "Page {} is {}, expected {}",
                    p.page_number + 1,
                    if landscape { "landscape" } else { "portrait" },
                    if ref_landscape { "landscape" } else { "portrait" }
                ),
                page: Some(p.page_number),
            });
        }
    }

    if all_consistent {
        checks.push(PreflightCheck {
            category: PreflightCategory::PageConsistency,
            severity: PreflightSeverity::Pass,
            title: "Page sizes consistent".to_string(),
            detail: format!("{} pages, all {:.1} x {:.1} pt", pages.len(), ref_width, ref_height),
            page: None,
        });
    }

    Ok(checks)
}
```

**Step 4: Run test to verify it passes**

Run: `cd rust-core && cargo test test_page_consistency -- --nocapture`
Expected: PASS

**Step 5: Commit**

```bash
git add rust-core/src/preflight/page_checks.rs rust-core/tests/preflight_test.rs
git commit -m "feat: add page consistency preflight check"
```

---

### Task 4: Preflight Orchestrator + UniFFI Export (Rust)

Ties ink coverage and page checks together. Exposes a single `run_preflight` function via UniFFI.

**Files:**
- Modify: `rust-core/src/preflight/mod.rs`
- Modify: `rust-core/src/lib.rs`
- Modify: `rust-core/tests/preflight_test.rs`

**Step 1: Write the failing test**

Add to `rust-core/tests/preflight_test.rs`:

```rust
use pdf_diff_core::preflight::run_preflight;
use pdf_diff_core::types::PreflightSeverity;

#[test]
fn test_run_preflight_returns_result() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }
    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let result = run_preflight(doc.as_ref(), 72, 300.0).unwrap();
    assert!(!result.checks.is_empty(), "Should have at least one check");
    assert!(result.summary.pass_count + result.summary.warn_count
        + result.summary.fail_count + result.summary.info_count > 0);
}
```

**Step 2: Run test to verify it fails**

Run: `cd rust-core && cargo test test_run_preflight -- --nocapture`
Expected: FAIL — function not found

**Step 3: Implement orchestrator**

Update `rust-core/src/preflight/mod.rs`:

```rust
pub mod ink_coverage;
pub mod page_checks;

use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{PreflightResult, PreflightSummary, PreflightCheck, PreflightSeverity,
                   PreflightCategory, InkCoverageResult};

/// Runs all Rust-side preflight checks on a document.
/// `dpi`: Resolution for rendering-based checks (72 is fine for ink coverage).
/// `max_ink_limit`: Maximum total ink percentage before warning (typically 300.0).
pub fn run_preflight(
    doc: &dyn PdfDocumentHandle,
    dpi: u32,
    max_ink_limit: f64,
) -> Result<PreflightResult, PdfError> {
    let mut checks = Vec::new();

    // Page consistency
    checks.extend(page_checks::check_page_consistency(doc)?);

    // Ink coverage (per page, only first page for speed; full scan is optional)
    let page_count = doc.page_count();
    for page in 0..page_count.min(10) {
        match ink_coverage::compute_ink_coverage(doc, page, dpi) {
            Ok(ink) => {
                let severity = if ink.total > max_ink_limit + 40.0 {
                    PreflightSeverity::Fail
                } else if ink.total > max_ink_limit {
                    PreflightSeverity::Warn
                } else {
                    PreflightSeverity::Pass
                };

                checks.push(PreflightCheck {
                    category: PreflightCategory::InkCoverage,
                    severity,
                    title: format!("Page {} ink coverage", page + 1),
                    detail: format!(
                        "C:{:.1}% M:{:.1}% Y:{:.1}% K:{:.1}% — Max total: {:.1}%",
                        ink.cyan, ink.magenta, ink.yellow, ink.black, ink.total
                    ),
                    page: Some(page),
                });
            }
            Err(e) => {
                checks.push(PreflightCheck {
                    category: PreflightCategory::InkCoverage,
                    severity: PreflightSeverity::Warn,
                    title: format!("Page {} ink coverage failed", page + 1),
                    detail: e.to_string(),
                    page: Some(page),
                });
            }
        }
    }

    let summary = compute_summary(&checks);
    Ok(PreflightResult { checks, summary })
}

fn compute_summary(checks: &[PreflightCheck]) -> PreflightSummary {
    let mut pass = 0u32;
    let mut warn = 0u32;
    let mut fail = 0u32;
    let mut info = 0u32;
    for c in checks {
        match c.severity {
            PreflightSeverity::Pass => pass += 1,
            PreflightSeverity::Warn => warn += 1,
            PreflightSeverity::Fail => fail += 1,
            PreflightSeverity::Info => info += 1,
        }
    }
    PreflightSummary {
        pass_count: pass,
        warn_count: warn,
        fail_count: fail,
        info_count: info,
    }
}
```

**Step 4: Export via UniFFI**

Add to `rust-core/src/lib.rs` after `compute_structural_diff_uniffi`:

```rust
#[uniffi::export]
pub fn run_preflight_uniffi(
    doc: &PdfDocument,
    dpi: u32,
    max_ink_limit: f64,
) -> Result<PreflightResult, PdfError> {
    preflight::run_preflight(doc.inner.as_ref(), dpi, max_ink_limit)
}
```

Also add to `PdfDocument` impl:

```rust
pub fn extract_page_text(&self, page: u32) -> Result<String, PdfError> {
    self.inner.extract_page_text(page)
}
```

**Step 5: Run tests**

Run: `cd rust-core && cargo test -- --nocapture`
Expected: All tests pass (13 existing + 3 new)

**Step 6: Build Rust + regenerate bindings**

Run: `make build-rust && make generate-bindings`
Expected: Success. Check `generated/pdf_diff_core.swift` contains `runPreflightUniffi` function.

**Step 7: Commit**

```bash
git add rust-core/src/preflight/ rust-core/src/lib.rs rust-core/src/types.rs rust-core/tests/preflight_test.rs
git commit -m "feat: add preflight orchestrator with ink coverage and page checks"
```

---

## Phase 2: Swift Preflight Models + Service

### Task 5: Preflight Swift Models

**Files:**
- Create: `PdfDiffApp/PdfDiff/Models/PreflightResult.swift`
- Test: `PdfDiffApp/PdfDiffTests/Models/PreflightResultTests.swift`

**Step 1: Write the failing test**

Create `PdfDiffApp/PdfDiffTests/Models/PreflightResultTests.swift`:

```swift
import Testing
@testable import PdfDiff

@Suite("PreflightResult Tests")
struct PreflightResultTests {

    @Test("severity ordering")
    func severityOrdering() {
        let fail = PreflightCheckSeverity.fail
        let warn = PreflightCheckSeverity.warn
        let pass = PreflightCheckSeverity.pass
        let info = PreflightCheckSeverity.info
        #expect(fail.rawValue == "fail")
        #expect(warn.rawValue == "warn")
        #expect(pass.rawValue == "pass")
        #expect(info.rawValue == "info")
    }

    @Test("summary computes from checks")
    func summaryComputation() {
        let checks: [PreflightCheckItem] = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "OK", detail: "", page: nil),
            PreflightCheckItem(category: .fonts, severity: .warn, title: "Subset", detail: "", page: 0),
            PreflightCheckItem(category: .images, severity: .fail, title: "Low res", detail: "", page: 1),
            PreflightCheckItem(category: .pageBoxes, severity: .info, title: "Info", detail: "", page: nil),
        ]
        let result = SwiftPreflightResult(checks: checks)
        #expect(result.summary.passCount == 1)
        #expect(result.summary.warnCount == 1)
        #expect(result.summary.failCount == 1)
        #expect(result.summary.infoCount == 1)
    }

    @Test("worst severity")
    func worstSeverity() {
        let checks: [PreflightCheckItem] = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "OK", detail: "", page: nil),
            PreflightCheckItem(category: .fonts, severity: .warn, title: "Subset", detail: "", page: nil),
        ]
        let result = SwiftPreflightResult(checks: checks)
        #expect(result.worstSeverity == .warn)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | grep -E '(Test|FAIL|error:)'`
Expected: FAIL — types not found

**Step 3: Create the Swift model**

Create `PdfDiffApp/PdfDiff/Models/PreflightResult.swift`:

```swift
import Foundation

enum PreflightCheckSeverity: String, Codable, CaseIterable, Comparable {
    case pass, info, warn, fail

    private var sortOrder: Int {
        switch self {
        case .pass: return 0
        case .info: return 1
        case .warn: return 2
        case .fail: return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum PreflightCheckCategory: String, Codable, CaseIterable {
    case inkCoverage, pageConsistency, pageBoxes, fonts, images
    case colorSpace, spotColors, transparency, overprint, barcodes

    var displayName: String {
        switch self {
        case .inkCoverage: return "Ink Coverage"
        case .pageConsistency: return "Page Consistency"
        case .pageBoxes: return "Page Boxes"
        case .fonts: return "Fonts"
        case .images: return "Images"
        case .colorSpace: return "Color Space"
        case .spotColors: return "Spot Colors"
        case .transparency: return "Transparency"
        case .overprint: return "Overprint"
        case .barcodes: return "Barcodes"
        }
    }
}

struct PreflightCheckItem: Identifiable {
    let id = UUID()
    let category: PreflightCheckCategory
    let severity: PreflightCheckSeverity
    let title: String
    let detail: String
    let page: UInt32?
}

struct PreflightSummaryResult {
    let passCount: Int
    let warnCount: Int
    let failCount: Int
    let infoCount: Int
}

struct SwiftPreflightResult {
    let checks: [PreflightCheckItem]

    var summary: PreflightSummaryResult {
        PreflightSummaryResult(
            passCount: checks.filter { $0.severity == .pass }.count,
            warnCount: checks.filter { $0.severity == .warn }.count,
            failCount: checks.filter { $0.severity == .fail }.count,
            infoCount: checks.filter { $0.severity == .info }.count
        )
    }

    var worstSeverity: PreflightCheckSeverity {
        checks.map(\.severity).max() ?? .pass
    }

    var groupedByCategory: [(category: PreflightCheckCategory, checks: [PreflightCheckItem])] {
        var groups: [PreflightCheckCategory: [PreflightCheckItem]] = [:]
        for check in checks {
            groups[check.category, default: []].append(check)
        }
        return PreflightCheckCategory.allCases.compactMap { cat in
            guard let items = groups[cat] else { return nil }
            return (category: cat, checks: items)
        }
    }
}
```

**Step 4: Regenerate Xcode project and run tests**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild test -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS'`
Expected: PreflightResult tests pass

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Models/PreflightResult.swift PdfDiffApp/PdfDiffTests/Models/PreflightResultTests.swift
git commit -m "feat: add Swift preflight result model with severity and categories"
```

---

### Task 6: Swift Preflight Service (PDFKit-based checks)

Uses PDFKit to check page boxes (bleed/trim/media) and font embedding — things the safe MuPDF API doesn't expose.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/PreflightService.swift`
- Test: `PdfDiffApp/PdfDiffTests/Services/PreflightServiceTests.swift`

**Step 1: Write the failing test**

Create `PdfDiffApp/PdfDiffTests/Services/PreflightServiceTests.swift`:

```swift
import Testing
import PDFKit
@testable import PdfDiff

@Suite("PreflightService Tests")
struct PreflightServiceTests {

    @Test("page box checks on valid PDF")
    func pageBoxChecks() {
        let service = PreflightService()
        // Use a known fixture or create a test PDF
        let bundle = Bundle(for: MockPDFService.self)
        // Falls back to empty checks if no fixture available
        let checks = service.checkPageBoxes(pdfPath: "/nonexistent.pdf")
        // Should return empty or error-level check for missing file
        #expect(checks.isEmpty || checks.first?.severity == .fail)
    }

    @Test("merge results combines Rust and Swift checks")
    func mergeResults() {
        let rustChecks = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "Ink OK", detail: "", page: nil),
        ]
        let swiftChecks = [
            PreflightCheckItem(category: .pageBoxes, severity: .warn, title: "No bleed", detail: "", page: 0),
        ]
        let result = PreflightService.mergeResults(rustChecks: rustChecks, swiftChecks: swiftChecks)
        #expect(result.checks.count == 2)
        #expect(result.worstSeverity == .warn)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test ...`
Expected: FAIL — PreflightService not found

**Step 3: Implement the service**

Create `PdfDiffApp/PdfDiff/Services/PreflightService.swift`:

```swift
import Foundation
import PDFKit

final class PreflightService: @unchecked Sendable {

    /// Check page boxes using PDFKit (BleedBox, TrimBox, MediaBox).
    func checkPageBoxes(pdfPath: String) -> [PreflightCheckItem] {
        guard let pdfDoc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            return [PreflightCheckItem(
                category: .pageBoxes, severity: .fail,
                title: "Cannot open PDF", detail: "Failed to open \(pdfPath)", page: nil
            )]
        }

        var checks: [PreflightCheckItem] = []
        for i in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }
            let pageNum = UInt32(i)

            let mediaBox = page.bounds(for: .mediaBox)
            let trimBox = page.bounds(for: .trimBox)
            let bleedBox = page.bounds(for: .bleedBox)

            // Check if trim box is defined (different from media box)
            let hasTrimBox = trimBox != mediaBox
            // Check if bleed box is defined and extends beyond trim
            let hasBleedBox = bleedBox != mediaBox && bleedBox != trimBox

            if !hasBleedBox {
                // Calculate bleed from difference between bleed and trim (or media)
                let referenceBox = hasTrimBox ? trimBox : mediaBox
                let bleedLeft = referenceBox.minX - bleedBox.minX
                let bleedRight = bleedBox.maxX - referenceBox.maxX
                let bleedTop = bleedBox.maxY - referenceBox.maxY
                let bleedBottom = referenceBox.minY - bleedBox.minY

                if !hasBleedBox {
                    checks.append(PreflightCheckItem(
                        category: .pageBoxes, severity: .fail,
                        title: "Page \(i + 1): No bleed defined",
                        detail: "BleedBox equals \(hasTrimBox ? "TrimBox" : "MediaBox"). Add 3mm+ bleed for print.",
                        page: pageNum
                    ))
                } else {
                    // Check minimum bleed (3mm = ~8.5 points)
                    let minBleed = min(bleedLeft, bleedRight, bleedTop, bleedBottom)
                    let minBleedMM = minBleed * 25.4 / 72.0
                    if minBleedMM < 3.0 {
                        checks.append(PreflightCheckItem(
                            category: .pageBoxes, severity: .warn,
                            title: "Page \(i + 1): Insufficient bleed",
                            detail: String(format: "Minimum bleed: %.1fmm (recommended: 3mm+)", minBleedMM),
                            page: pageNum
                        ))
                    }
                }
            }

            if !hasTrimBox && !hasBleedBox {
                // No trim or bleed defined at all — just media box
                checks.append(PreflightCheckItem(
                    category: .pageBoxes, severity: .info,
                    title: "Page \(i + 1): Only MediaBox defined",
                    detail: String(format: "MediaBox: %.0f x %.0f pt. No TrimBox or BleedBox set.",
                                   mediaBox.width, mediaBox.height),
                    page: pageNum
                ))
            }
        }

        if checks.isEmpty {
            checks.append(PreflightCheckItem(
                category: .pageBoxes, severity: .pass,
                title: "Page boxes OK",
                detail: "All pages have proper TrimBox and BleedBox defined.",
                page: nil
            ))
        }

        return checks
    }

    /// Merge Rust-side and Swift-side preflight results into one.
    static func mergeResults(
        rustChecks: [PreflightCheckItem],
        swiftChecks: [PreflightCheckItem]
    ) -> SwiftPreflightResult {
        SwiftPreflightResult(checks: rustChecks + swiftChecks)
    }
}
```

**Step 4: Regenerate Xcode project and run tests**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild test -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS'`
Expected: Tests pass

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/PreflightService.swift PdfDiffApp/PdfDiffTests/Services/PreflightServiceTests.swift
git commit -m "feat: add Swift PreflightService with PDFKit page box checks"
```

---

### Task 7: Preflight Panel UI

A new collapsible panel showing preflight results below the page canvas in InspectorView.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/PreflightPanel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`

**Step 1: Create the PreflightPanel view**

Create `PdfDiffApp/PdfDiff/Views/Inspector/PreflightPanel.swift`:

```swift
import SwiftUI

struct PreflightPanel: View {
    let result: SwiftPreflightResult
    var onNavigateToPage: ((UInt32) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary bar
            summaryBar
            Divider()

            // Grouped checks
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.groupedByCategory, id: \.category) { group in
                        DisclosureGroup {
                            ForEach(group.checks) { check in
                                checkRow(check)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                severityIcon(worstIn: group.checks)
                                Text(group.category.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(group.checks.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text("Preflight")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                if result.summary.passCount > 0 {
                    Label("\(result.summary.passCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if result.summary.warnCount > 0 {
                    Label("\(result.summary.warnCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if result.summary.failCount > 0 {
                    Label("\(result.summary.failCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if result.summary.infoCount > 0 {
                    Label("\(result.summary.infoCount)", systemImage: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func checkRow(_ check: PreflightCheckItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            severityDot(check.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.caption)
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let page = check.page {
                Button("p.\(page + 1)") {
                    onNavigateToPage?(page)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func severityIcon(worstIn checks: [PreflightCheckItem]) -> some View {
        let worst = checks.map(\.severity).max() ?? .pass
        return severityDot(worst)
    }

    @ViewBuilder
    private func severityDot(_ severity: PreflightCheckSeverity) -> some View {
        switch severity {
        case .pass:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warn:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fail:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
        }
    }
}
```

**Step 2: Regenerate Xcode project and build**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/PreflightPanel.swift
git commit -m "feat: add PreflightPanel view with severity badges and grouped checks"
```

---

### Task 8: Wire Preflight into InspectorViewModel

Adds preflight state to InspectorViewModel and runs checks automatically on document load.

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`
- Modify: `PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift`

**Step 1: Add preflight state to InspectorViewModel**

Add after `var showPins = true` (around line 21):

```swift
    // Preflight state
    var preflightResult: SwiftPreflightResult?
    var isPreflighting = false
```

Add a `preflightService` property:

```swift
    private let preflightService = PreflightService()
```

Add `runPreflight()` method after `zoomFit()`:

```swift
    func runPreflight() {
        guard let doc = document else { return }
        isPreflighting = true

        // Swift-side checks (PDFKit)
        let swiftChecks = preflightService.checkPageBoxes(pdfPath: doc.path)

        // TODO: Add Rust-side checks via UniFFI when real PDF service is wired
        // For now, just use Swift checks
        preflightResult = PreflightService.mergeResults(rustChecks: [], swiftChecks: swiftChecks)
        isPreflighting = false
    }
```

In `loadDocument()`, add after the metadata loading block (after `await renderCurrentPage()`):

```swift
        runPreflight()
```

**Step 2: Add PreflightPanel to InspectorView**

In `InspectorView.swift`, replace the MetadataPanel section at the bottom of the VSplitView with:

```swift
            // Preflight + Metadata panel
            VStack(spacing: 0) {
                if let preflight = viewModel.preflightResult {
                    PreflightPanel(
                        result: preflight,
                        onNavigateToPage: { page in
                            viewModel.currentPage = page
                            Task { await viewModel.loadDocument(viewModel.document!) }
                        }
                    )
                    Divider()
                } else if viewModel.isPreflighting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Running preflight...").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    Divider()
                }

                MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
            }
            .frame(minHeight: 150, maxHeight: 300)
```

**Step 3: Add tests**

Add to `InspectorViewModelTests.swift`:

```swift
    @Test("preflight runs on document load")
    func preflightOnLoad() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)
        // Should have run preflight (may have results or be nil if path is mock)
        #expect(vm.isPreflighting == false)
    }
```

**Step 4: Regenerate Xcode project and build**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift
git commit -m "feat: wire preflight into InspectorViewModel with auto-run on load"
```

---

## Phase 3: Barcode Detection

### Task 9: BarcodeDetectionService

Uses Apple's Vision framework to detect and decode barcodes in rendered page images.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/BarcodeDetectionService.swift`
- Create: `PdfDiffApp/PdfDiff/Models/DetectedBarcode.swift`
- Test: `PdfDiffApp/PdfDiffTests/Services/BarcodeDetectionServiceTests.swift`

**Step 1: Create the barcode model**

Create `PdfDiffApp/PdfDiff/Models/DetectedBarcode.swift`:

```swift
import Foundation

struct DetectedBarcode: Identifiable {
    let id = UUID()
    let symbology: String        // e.g., "EAN-13", "QR", "Code 128"
    let payload: String           // decoded data
    let boundingBox: CGRect       // normalized 0-1 coordinates
    let confidence: Float         // 0-1

    var displaySymbology: String {
        symbology
            .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}
```

**Step 2: Create the service**

Create `PdfDiffApp/PdfDiff/Services/BarcodeDetectionService.swift`:

```swift
import Foundation
import AppKit
import Vision

final class BarcodeDetectionService: @unchecked Sendable {

    func detectBarcodes(in image: NSImage) async -> [DetectedBarcode] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let barcodes = results.compactMap { obs -> DetectedBarcode? in
                    guard let payload = obs.payloadStringValue else { return nil }
                    // Vision returns bounding box in normalized coordinates (origin bottom-left)
                    // Convert to top-left origin for SwiftUI
                    let box = obs.boundingBox
                    let flipped = CGRect(
                        x: box.minX,
                        y: 1.0 - box.maxY,
                        width: box.width,
                        height: box.height
                    )
                    return DetectedBarcode(
                        symbology: obs.symbology.rawValue,
                        payload: payload,
                        boundingBox: flipped,
                        confidence: obs.confidence
                    )
                }
                continuation.resume(returning: barcodes)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
```

**Step 3: Create test**

Create `PdfDiffApp/PdfDiffTests/Services/BarcodeDetectionServiceTests.swift`:

```swift
import Testing
import AppKit
@testable import PdfDiff

@Suite("BarcodeDetectionService Tests")
struct BarcodeDetectionServiceTests {

    @Test("returns empty for blank image")
    func blankImage() async {
        let service = BarcodeDetectionService()
        let blank = NSImage(size: NSSize(width: 100, height: 100))
        let results = await service.detectBarcodes(in: blank)
        #expect(results.isEmpty)
    }

    @Test("detected barcode model properties")
    func modelProperties() {
        let barcode = DetectedBarcode(
            symbology: "VNBarcodeSymbologyEAN13",
            payload: "5901234123457",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            confidence: 0.95
        )
        #expect(barcode.displaySymbology == "EAN13")
        #expect(barcode.payload == "5901234123457")
    }
}
```

**Step 4: Regenerate Xcode project, build and test**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/BarcodeDetectionService.swift PdfDiffApp/PdfDiff/Models/DetectedBarcode.swift PdfDiffApp/PdfDiffTests/Services/BarcodeDetectionServiceTests.swift
git commit -m "feat: add BarcodeDetectionService using Vision framework"
```

---

### Task 10: Wire Barcode Detection into Inspector

Adds barcode results to the preflight panel and shows barcode overlay on the page canvas.

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`
- Modify: `PdfDiffApp/PdfDiff/Services/PreflightService.swift`

**Step 1: Add barcode state to InspectorViewModel**

Add after preflight state:

```swift
    // Barcode state
    var detectedBarcodes: [DetectedBarcode] = []
    var showBarcodeOverlay = true
```

Add `barcodeService`:

```swift
    private let barcodeService = BarcodeDetectionService()
```

Add `detectBarcodes()` method:

```swift
    func detectBarcodes() async {
        guard let image = renderedImage else { return }
        detectedBarcodes = await barcodeService.detectBarcodes(in: image)

        // Add barcode results to preflight
        let barcodeChecks: [PreflightCheckItem]
        if detectedBarcodes.isEmpty {
            barcodeChecks = [PreflightCheckItem(
                category: .barcodes, severity: .info,
                title: "No barcodes detected", detail: "No barcodes found on this page.", page: currentPage
            )]
        } else {
            barcodeChecks = detectedBarcodes.map { barcode in
                PreflightCheckItem(
                    category: .barcodes, severity: .pass,
                    title: "\(barcode.displaySymbology) detected",
                    detail: barcode.payload,
                    page: currentPage
                )
            }
        }

        // Merge with existing preflight result
        if let existing = preflightResult {
            let nonBarcodeChecks = existing.checks.filter { $0.category != .barcodes }
            preflightResult = SwiftPreflightResult(checks: nonBarcodeChecks + barcodeChecks)
        } else {
            preflightResult = SwiftPreflightResult(checks: barcodeChecks)
        }
    }
```

In `loadDocument()`, after `runPreflight()`:

```swift
        await detectBarcodes()
```

**Step 2: Add barcode overlay to InspectorView page canvas**

In `InspectorView.swift`, inside the `.overlay` block of the ZoomableContainer content (after the issue pin overlay), add:

```swift
                    // Barcode overlay
                    if viewModel.showBarcodeOverlay && !viewModel.detectedBarcodes.isEmpty {
                        GeometryReader { geo in
                            ForEach(viewModel.detectedBarcodes) { barcode in
                                Rectangle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .background(Color.blue.opacity(0.1))
                                    .frame(
                                        width: barcode.boundingBox.width * geo.size.width,
                                        height: barcode.boundingBox.height * geo.size.height
                                    )
                                    .position(
                                        x: (barcode.boundingBox.midX) * geo.size.width,
                                        y: (barcode.boundingBox.midY) * geo.size.height
                                    )
                            }
                        }
                    }
```

**Step 3: Regenerate, build, test**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift
git commit -m "feat: wire barcode detection into Inspector with overlay and preflight integration"
```

---

## Phase 4: Separation Preview

### Task 11: Wire MuPDF Separation Rendering (Rust)

The separation trait methods exist but return placeholders. For v1.0, we implement CMYK channel splitting — rendering the page in CMYK and extracting individual channels as grayscale bitmaps.

**Files:**
- Create: `rust-core/src/preflight/separations.rs`
- Modify: `rust-core/src/preflight/mod.rs`
- Modify: `rust-core/src/lib.rs`
- Test: `rust-core/tests/preflight_test.rs`

**Step 1: Write the failing test**

Add to `rust-core/tests/preflight_test.rs`:

```rust
use pdf_diff_core::preflight::separations::extract_cmyk_channels;

#[test]
fn test_extract_cmyk_channels() {
    let fixture = helpers::fixture_path("simple.pdf");
    if !fixture.exists() {
        helpers::create_simple_pdf(&fixture);
    }
    let engine = MuPdfEngine::new();
    let doc = engine.open(fixture.to_str().unwrap()).unwrap();

    let channels = extract_cmyk_channels(doc.as_ref(), 0, 72).unwrap();
    assert_eq!(channels.len(), 4, "Should have C, M, Y, K channels");
    assert_eq!(channels[0].name, "Cyan");
    assert_eq!(channels[1].name, "Magenta");
    assert_eq!(channels[2].name, "Yellow");
    assert_eq!(channels[3].name, "Black");
    // Each channel is a grayscale bitmap (1 byte per pixel)
    let expected_size = (channels[0].width * channels[0].height) as usize;
    assert_eq!(channels[0].bitmap.len(), expected_size);
}
```

**Step 2: Implement CMYK channel extraction**

Create `rust-core/src/preflight/separations.rs`:

```rust
use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{RenderColorspace, RenderedPage};

/// A single color channel extracted from CMYK rendering.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ChannelBitmap {
    pub name: String,
    pub bitmap: Vec<u8>,   // Grayscale, 1 byte per pixel (0=none, 255=full coverage)
    pub width: u32,
    pub height: u32,
    pub coverage_percent: f64,
}

/// Renders a page in CMYK and splits into individual channel bitmaps.
pub fn extract_cmyk_channels(
    doc: &dyn PdfDocumentHandle,
    page: u32,
    dpi: u32,
) -> Result<Vec<ChannelBitmap>, PdfError> {
    let rendered = doc.render_page(page, dpi, &RenderColorspace::Cmyk)?;

    // MuPDF CMYK pixmap: 5 bytes per pixel (C, M, Y, K, A)
    let bpp = 5;
    let pixel_count = (rendered.width * rendered.height) as usize;

    if rendered.bitmap.len() < pixel_count * bpp {
        return Err(PdfError::RenderingFailed {
            detail: format!(
                "CMYK bitmap size mismatch: {} bytes for {}x{} (expected {})",
                rendered.bitmap.len(), rendered.width, rendered.height, pixel_count * bpp
            ),
        });
    }

    let channel_names = ["Cyan", "Magenta", "Yellow", "Black"];
    let mut channels = Vec::with_capacity(4);

    for (ch_idx, name) in channel_names.iter().enumerate() {
        let mut channel_data = Vec::with_capacity(pixel_count);
        let mut sum: f64 = 0.0;

        for i in 0..pixel_count {
            let value = rendered.bitmap[i * bpp + ch_idx];
            channel_data.push(value);
            sum += value as f64;
        }

        let coverage = sum / (pixel_count as f64 * 255.0) * 100.0;

        channels.push(ChannelBitmap {
            name: name.to_string(),
            bitmap: channel_data,
            width: rendered.width,
            height: rendered.height,
            coverage_percent: coverage,
        });
    }

    Ok(channels)
}
```

Update `rust-core/src/preflight/mod.rs`:

```rust
pub mod ink_coverage;
pub mod page_checks;
pub mod separations;
```

**Step 3: Export via UniFFI**

Add to `rust-core/src/lib.rs` after `run_preflight_uniffi`:

```rust
#[uniffi::export]
pub fn extract_cmyk_channels_uniffi(
    doc: &PdfDocument,
    page: u32,
    dpi: u32,
) -> Result<Vec<preflight::separations::ChannelBitmap>, PdfError> {
    preflight::separations::extract_cmyk_channels(doc.inner.as_ref(), page, dpi)
}
```

**Step 4: Run tests and build**

Run: `cd rust-core && cargo test -- --nocapture && cd .. && make build-rust && make generate-bindings`
Expected: All tests pass, bindings generated

**Step 5: Commit**

```bash
git add rust-core/src/preflight/separations.rs rust-core/src/preflight/mod.rs rust-core/src/lib.rs rust-core/tests/preflight_test.rs
git commit -m "feat: add CMYK channel extraction for separation preview"
```

---

### Task 12: Separation Viewer UI

New view mode in Inspector — a "Separations" toggle that shows CMYK channel viewer with toggles and coverage percentages.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/SeparationViewer.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`

**Step 1: Create SeparationViewer**

Create `PdfDiffApp/PdfDiff/Views/Inspector/SeparationViewer.swift`:

```swift
import SwiftUI

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let image: NSImage
    let coverage: Double
    var isEnabled: Bool = true
}

struct SeparationViewer: View {
    @Binding var channels: [ChannelInfo]
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        HStack(spacing: 0) {
            // Composite preview
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    Color.white
                    ForEach(channels.filter(\.isEnabled)) { channel in
                        Image(nsImage: channel.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blendMode(.multiply)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Channel list
            VStack(alignment: .leading, spacing: 8) {
                Text("Separations")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach($channels) { $channel in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $channel.isEnabled)
                            .toggleStyle(.checkbox)
                        Circle()
                            .fill(channel.color)
                            .frame(width: 12, height: 12)
                        Text(channel.name)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f%%", channel.coverage))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                let totalCoverage = channels.filter(\.isEnabled).reduce(0.0) { $0 + $1.coverage }
                HStack {
                    Text("Total ink")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f%%", totalCoverage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(totalCoverage > 300 ? .red : .secondary)
                }

                Spacer()
            }
            .padding(12)
            .frame(width: 200)
        }
    }
}
```

**Step 2: Add separation state to InspectorViewModel**

Add to InspectorViewModel:

```swift
    // Separation state
    var showSeparations = false
    var separationChannels: [ChannelInfo] = []
    var isLoadingSeparations = false
```

Add method:

```swift
    func loadSeparations() async {
        guard let doc = document, let image = renderedImage else { return }
        isLoadingSeparations = true
        defer { isLoadingSeparations = false }

        // For now, create tinted channel images from the rendered CMYK page
        // In future, use Rust's extract_cmyk_channels_uniffi for real separation data
        // Placeholder: split the page image into tinted CMYK approximations
        let size = image.size
        let colors: [(String, NSColor)] = [
            ("Cyan", NSColor.cyan),
            ("Magenta", NSColor.magenta),
            ("Yellow", NSColor.yellow),
            ("Black", NSColor.black),
        ]

        separationChannels = colors.map { name, color in
            ChannelInfo(
                name: name,
                color: Color(nsColor: color),
                image: image, // Placeholder — real channels from Rust later
                coverage: 0.0
            )
        }
    }
```

**Step 3: Add segmented picker in InspectorView toolbar**

In `InspectorView.swift` toolbar, add after page navigation and before the divider:

```swift
            Picker("", selection: $viewModel.showSeparations) {
                Text("Page").tag(false)
                Text("Separations").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: viewModel.showSeparations) { _, show in
                if show && viewModel.separationChannels.isEmpty {
                    Task { await viewModel.loadSeparations() }
                }
            }
```

In the `pageCanvas` computed property, wrap the existing content with a condition:

```swift
    @ViewBuilder
    private var pageCanvas: some View {
        if viewModel.showSeparations {
            SeparationViewer(
                channels: $viewModel.separationChannels,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        } else if viewModel.isRendering {
            // ... existing rendering/image/pin code
        }
    }
```

**Step 4: Regenerate, build**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/SeparationViewer.swift PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift
git commit -m "feat: add separation viewer with CMYK channel toggles"
```

---

## Phase 5: Report Generation

### Task 13: ReportGenerator Service

Generates PDF and Markdown reports consolidating all QC results.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/ReportGenerator.swift`
- Test: `PdfDiffApp/PdfDiffTests/Services/ReportGeneratorTests.swift`

**Step 1: Write the failing test**

Create `PdfDiffApp/PdfDiffTests/Services/ReportGeneratorTests.swift`:

```swift
import Testing
import AppKit
@testable import PdfDiff

@Suite("ReportGenerator Tests")
struct ReportGeneratorTests {

    @Test("markdown report for inspection")
    func markdownInspectionReport() {
        let preflight = SwiftPreflightResult(checks: [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "Ink OK", detail: "Max 220%", page: nil),
            PreflightCheckItem(category: .pageBoxes, severity: .warn, title: "No bleed", detail: "Page 1", page: 0),
        ])
        let generator = ReportGenerator()
        let markdown = generator.generateMarkdown(
            documentName: "test.pdf",
            preflight: preflight,
            barcodes: [],
            inspection: nil,
            aiNarrative: nil
        )
        #expect(markdown.contains("test.pdf"))
        #expect(markdown.contains("Ink OK"))
        #expect(markdown.contains("No bleed"))
        #expect(markdown.contains("Preflight"))
    }

    @Test("markdown includes barcodes")
    func markdownWithBarcodes() {
        let barcodes = [
            DetectedBarcode(symbology: "EAN13", payload: "123456", boundingBox: .zero, confidence: 1.0)
        ]
        let generator = ReportGenerator()
        let markdown = generator.generateMarkdown(
            documentName: "test.pdf",
            preflight: SwiftPreflightResult(checks: []),
            barcodes: barcodes,
            inspection: nil,
            aiNarrative: nil
        )
        #expect(markdown.contains("123456"))
        #expect(markdown.contains("EAN13"))
    }
}
```

**Step 2: Implement ReportGenerator**

Create `PdfDiffApp/PdfDiff/Services/ReportGenerator.swift`:

```swift
import Foundation
import AppKit
import PDFKit

final class ReportGenerator {

    // MARK: - Markdown Report

    func generateMarkdown(
        documentName: String,
        preflight: SwiftPreflightResult?,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?,
        aiNarrative: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# QC Report: \(documentName)")
        lines.append("")
        lines.append("**Generated:** \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        // AI Narrative (if available)
        if let narrative = aiNarrative, !narrative.isEmpty {
            lines.append("## Summary")
            lines.append(narrative)
            lines.append("")
        }

        // Preflight Results
        if let preflight = preflight, !preflight.checks.isEmpty {
            lines.append("## Preflight Results")
            lines.append("")
            let s = preflight.summary
            lines.append("| Status | Count |")
            lines.append("|--------|-------|")
            if s.passCount > 0 { lines.append("| Pass | \(s.passCount) |") }
            if s.warnCount > 0 { lines.append("| Warning | \(s.warnCount) |") }
            if s.failCount > 0 { lines.append("| Fail | \(s.failCount) |") }
            if s.infoCount > 0 { lines.append("| Info | \(s.infoCount) |") }
            lines.append("")

            for group in preflight.groupedByCategory {
                lines.append("### \(group.category.displayName)")
                for check in group.checks {
                    let icon = severityIcon(check.severity)
                    lines.append("- \(icon) **\(check.title)**")
                    if !check.detail.isEmpty {
                        lines.append("  \(check.detail)")
                    }
                }
                lines.append("")
            }
        }

        // Barcodes
        if !barcodes.isEmpty {
            lines.append("## Barcodes Detected")
            lines.append("")
            lines.append("| Type | Data |")
            lines.append("|------|------|")
            for barcode in barcodes {
                lines.append("| \(barcode.displaySymbology) | `\(barcode.payload)` |")
            }
            lines.append("")
        }

        // AI Inspection
        if let inspection = inspection {
            lines.append("## AI Inspection")
            lines.append("")
            lines.append(inspection.summary)
            lines.append("")
            for issue in inspection.issues {
                let icon = issue.severity == .fail ? "RED" : issue.severity == .warn ? "YELLOW" : "GREEN"
                lines.append("- [\(icon)] **\(issue.title)**: \(issue.detail)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - PDF Report

    func generatePDF(
        documentName: String,
        preflight: SwiftPreflightResult?,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?,
        aiNarrative: String?,
        pageImage: NSImage?
    ) -> Data? {
        let markdown = generateMarkdown(
            documentName: documentName,
            preflight: preflight,
            barcodes: barcodes,
            inspection: inspection,
            aiNarrative: aiNarrative
        )

        // Use NSAttributedString to create a simple PDF from the markdown text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]
        let attrStr = NSAttributedString(string: markdown, attributes: attrs)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
            height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        ))
        textView.textStorage?.setAttributedString(attrStr)

        let data = textView.dataWithPDF(inside: textView.bounds)
        return data
    }

    private func severityIcon(_ severity: PreflightCheckSeverity) -> String {
        switch severity {
        case .pass: return "PASS"
        case .warn: return "WARN"
        case .fail: return "FAIL"
        case .info: return "INFO"
        }
    }
}
```

**Step 3: Regenerate, build, test**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/ReportGenerator.swift PdfDiffApp/PdfDiffTests/Services/ReportGeneratorTests.swift
git commit -m "feat: add ReportGenerator service with Markdown and PDF output"
```

---

### Task 14: Export Report UI

Adds "Export Report" button to Inspector toolbar with save dialog.

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`

**Step 1: Add export method to InspectorViewModel**

Add to InspectorViewModel:

```swift
    private let reportGenerator = ReportGenerator()

    func exportReport(format: ReportFormat) {
        guard let doc = document else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .pdf
            ? [.pdf]
            : [.plainText]
        panel.nameFieldStringValue = "\(doc.fileName.replacingOccurrences(of: ".pdf", with: ""))-qc-report.\(format == .pdf ? "pdf" : "md")"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch format {
        case .pdf:
            if let data = reportGenerator.generatePDF(
                documentName: doc.fileName,
                preflight: preflightResult,
                barcodes: detectedBarcodes,
                inspection: inspectionResult,
                aiNarrative: nil,
                pageImage: renderedImage
            ) {
                try? data.write(to: url)
            }
        case .markdown:
            let markdown = reportGenerator.generateMarkdown(
                documentName: doc.fileName,
                preflight: preflightResult,
                barcodes: detectedBarcodes,
                inspection: inspectionResult,
                aiNarrative: nil
            )
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    enum ReportFormat {
        case pdf, markdown
    }
```

**Step 2: Add Export button to InspectorView toolbar**

In InspectorView toolbar, add before the Inspect button:

```swift
            Menu {
                Button("Export as PDF...") { viewModel.exportReport(format: .pdf) }
                Button("Export as Markdown...") { viewModel.exportReport(format: .markdown) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
            }
            .disabled(viewModel.document == nil)

            Divider().frame(height: 20)
```

**Step 3: Regenerate, build**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift
git commit -m "feat: add Export Report button with PDF and Markdown output"
```

---

## Phase 6: Batch Comparison

### Task 15: Batch Data Model and Matching Logic

**Files:**
- Create: `PdfDiffApp/PdfDiff/Models/BatchComparison.swift`
- Create: `PdfDiffApp/PdfDiff/ViewModels/BatchViewModel.swift`
- Test: `PdfDiffApp/PdfDiffTests/Models/BatchComparisonTests.swift`

**Step 1: Write the failing test**

Create `PdfDiffApp/PdfDiffTests/Models/BatchComparisonTests.swift`:

```swift
import Testing
@testable import PdfDiff

@Suite("BatchComparison Tests")
struct BatchComparisonTests {

    @Test("auto-match by name similarity")
    func autoMatch() {
        let files = [
            "artwork_v1.pdf", "artwork_v2.pdf",
            "label_old.pdf", "label_new.pdf",
            "unmatched.pdf"
        ]
        let pairs = BatchMatcher.autoMatch(fileNames: files)
        #expect(pairs.count == 2)
        #expect(pairs[0].leftName == "artwork_v1.pdf")
        #expect(pairs[0].rightName == "artwork_v2.pdf")
    }

    @Test("batch pair status")
    func pairStatus() {
        var pair = BatchPair(leftPath: "/a.pdf", rightPath: "/b.pdf", leftName: "a.pdf", rightName: "b.pdf")
        #expect(pair.status == .pending)
        pair.status = .complete
        pair.similarityScore = 0.95
        #expect(pair.similarityScore == 0.95)
    }
}
```

**Step 2: Create the model**

Create `PdfDiffApp/PdfDiff/Models/BatchComparison.swift`:

```swift
import Foundation

struct BatchPair: Identifiable {
    let id = UUID()
    let leftPath: String
    let rightPath: String
    let leftName: String
    let rightName: String
    var status: BatchPairStatus = .pending
    var similarityScore: Double?
    var preflightSummary: PreflightSummaryResult?
    var errorMessage: String?
}

enum BatchPairStatus {
    case pending, processing, complete, error
}

struct BatchMatcher {
    /// Auto-match files by name similarity.
    /// Looks for version patterns: v1/v2, old/new, _1/_2, -rev1/-rev2
    static func autoMatch(fileNames: [String]) -> [(leftName: String, rightName: String)] {
        var used = Set<Int>()
        var pairs: [(String, String)] = []

        for i in 0..<fileNames.count {
            guard !used.contains(i) else { continue }
            let nameI = fileNames[i]
            let baseI = normalizeForMatching(nameI)

            for j in (i+1)..<fileNames.count {
                guard !used.contains(j) else { continue }
                let nameJ = fileNames[j]
                let baseJ = normalizeForMatching(nameJ)

                if baseI == baseJ && nameI != nameJ {
                    // Sort so "v1"/"old" comes first
                    let sorted = [nameI, nameJ].sorted()
                    pairs.append((sorted[0], sorted[1]))
                    used.insert(i)
                    used.insert(j)
                    break
                }
            }
        }

        return pairs
    }

    private static func normalizeForMatching(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: ".pdf", with: "")
            .replacingOccurrences(of: "_v1", with: "")
            .replacingOccurrences(of: "_v2", with: "")
            .replacingOccurrences(of: "_v3", with: "")
            .replacingOccurrences(of: "_old", with: "")
            .replacingOccurrences(of: "_new", with: "")
            .replacingOccurrences(of: "-v1", with: "")
            .replacingOccurrences(of: "-v2", with: "")
            .replacingOccurrences(of: "-v3", with: "")
            .replacingOccurrences(of: "-old", with: "")
            .replacingOccurrences(of: "-new", with: "")
            .replacingOccurrences(of: "_rev1", with: "")
            .replacingOccurrences(of: "_rev2", with: "")
            .replacingOccurrences(of: "_1", with: "")
            .replacingOccurrences(of: "_2", with: "")
    }
}
```

**Step 3: Create BatchViewModel**

Create `PdfDiffApp/PdfDiff/ViewModels/BatchViewModel.swift`:

```swift
import SwiftUI

@Observable @MainActor
final class BatchViewModel {
    var pairs: [BatchPair] = []
    var isProcessing = false

    private let pdfService: PDFServiceProtocol
    private let preflightService = PreflightService()

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func addFolder(url: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension.lowercased() == "pdf" }) else { return }

        let names = files.map { $0.lastPathComponent }
        let matched = BatchMatcher.autoMatch(fileNames: names)

        pairs = matched.map { match in
            let leftURL = files.first { $0.lastPathComponent == match.leftName }!
            let rightURL = files.first { $0.lastPathComponent == match.rightName }!
            return BatchPair(
                leftPath: leftURL.path,
                rightPath: rightURL.path,
                leftName: match.leftName,
                rightName: match.rightName
            )
        }
    }

    func processAll() async {
        isProcessing = true
        defer { isProcessing = false }

        for i in pairs.indices {
            pairs[i].status = .processing
            do {
                let left = try pdfService.openDocument(path: pairs[i].leftPath)
                let right = try pdfService.openDocument(path: pairs[i].rightPath)
                let diff = try pdfService.computePixelDiff(
                    left: left, right: right, page: 0, dpi: 72, sensitivity: 0.05
                )
                pairs[i].similarityScore = diff.similarityScore
                pairs[i].status = .complete
            } catch {
                pairs[i].status = .error
                pairs[i].errorMessage = error.localizedDescription
            }
        }
    }

    var completedCount: Int { pairs.filter { $0.status == .complete }.count }
    var totalCount: Int { pairs.count }
}
```

**Step 4: Regenerate, build, test**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Models/BatchComparison.swift PdfDiffApp/PdfDiff/ViewModels/BatchViewModel.swift PdfDiffApp/PdfDiffTests/Models/BatchComparisonTests.swift
git commit -m "feat: add batch comparison model with auto-matching and BatchViewModel"
```

---

### Task 16: Batch View UI

New tab in DetailAreaView for batch processing.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Batch/BatchView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/AppView.swift` (add Batch tab)
- Modify: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift` (add batch tab enum + viewModel)

**Step 1: Create BatchView**

Create `PdfDiffApp/PdfDiff/Views/Batch/BatchView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct BatchView: View {
    @State var viewModel: BatchViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.pairs.isEmpty {
                dropZone
            } else {
                batchToolbar
                Divider()
                batchTable
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a folder of PDFs here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Files will be auto-matched by name (v1/v2, old/new)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        Task { @MainActor in
                            viewModel.addFolder(url: url)
                        }
                    }
                }
            }
            return true
        }
    }

    private var batchToolbar: some View {
        HStack {
            Text("\(viewModel.pairs.count) pairs found")
                .font(.headline)

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                    .font(.caption)
            }

            Button("Process All") {
                Task { await viewModel.processAll() }
            }
            .disabled(viewModel.isProcessing || viewModel.pairs.isEmpty)

            Button("Clear") {
                viewModel.pairs = []
            }
            .disabled(viewModel.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var batchTable: some View {
        Table(viewModel.pairs) {
            TableColumn("Left") { pair in Text(pair.leftName).font(.caption) }
            TableColumn("Right") { pair in Text(pair.rightName).font(.caption) }
            TableColumn("Similarity") { pair in
                if let score = pair.similarityScore {
                    Text(String(format: "%.1f%%", score * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(score > 0.99 ? .green : score > 0.9 ? .orange : .red)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(80)
            TableColumn("Status") { pair in
                switch pair.status {
                case .pending: Text("Pending").font(.caption).foregroundStyle(.secondary)
                case .processing: ProgressView().controlSize(.mini)
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .width(60)
        }
    }
}
```

**Step 2: Add Batch tab to AppViewModel and DetailAreaView**

This requires reading and modifying `AppViewModel.swift` and the detail area view. Add `.batch` case to the tab enum and wire up the BatchViewModel.

In `AppViewModel.swift`, add to the `ActiveTab` enum:
```swift
case batch
```

Add property:
```swift
var batchViewModel: BatchViewModel
```

Initialize in `init`:
```swift
self.batchViewModel = BatchViewModel(pdfService: pdfService)
```

In the detail area view (likely `AppView.swift` or `DetailAreaView.swift`), add the batch tab option and render `BatchView` when selected.

**Step 3: Regenerate, build**

Run: `cd PdfDiffApp && xcodegen generate && cd .. && xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Batch/ PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift PdfDiffApp/PdfDiff/Views/AppView.swift
git commit -m "feat: add batch comparison view with folder drop and results table"
```

---

## Phase 7: AI-Enhanced Reports + Polish

### Task 17: AI Narrative for Reports

When exporting a report with an API key configured, optionally include an AI-generated narrative summarizing all findings.

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`

**Step 1: Add narrative generation method to AIAnalysisServiceProtocol**

Add to `AIAnalysisService.swift` protocol:

```swift
    func generateNarrative(
        preflight: SwiftPreflightResult,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?
    ) async throws -> String
```

**Step 2: Implement in OpenRouterAIService**

Add method that sends preflight summary + barcode data + inspection issues to the LLM with a prompt asking for a concise plain-language summary suitable for client communication. Return the narrative string.

**Step 3: Wire into export flow**

In InspectorViewModel's `exportReport()`, if an API key is configured, run AI narrative generation before creating the report. Pass the narrative to ReportGenerator.

**Step 4: Build and test**

Run: `xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift
git commit -m "feat: add AI-generated narrative for QC reports"
```

---

### Task 18: LRU Cache Integration

Cap rendered page cache at ~500MB to prevent memory issues with batch processing.

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/RenderCache.swift`
- Modify: `PdfDiffApp/PdfDiff/Services/MockPDFService.swift`

**Step 1: Create RenderCache**

```swift
import Foundation
import AppKit

final class RenderCache: @unchecked Sendable {
    private var cache: [String: (image: NSImage, size: Int)] = [:]
    private var accessOrder: [String] = []
    private let maxBytes: Int
    private var currentBytes: Int = 0
    private let lock = NSLock()

    init(maxBytes: Int = 500_000_000) { // 500MB
        self.maxBytes = maxBytes
    }

    func get(key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let entry = cache[key] {
            // Move to end (most recently used)
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            return entry.image
        }
        return nil
    }

    func set(key: String, image: NSImage) {
        let size = estimateSize(image)
        lock.lock()
        defer { lock.unlock() }

        // Evict until there's room
        while currentBytes + size > maxBytes && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            if let entry = cache.removeValue(forKey: oldest) {
                currentBytes -= entry.size
            }
        }

        cache[key] = (image, size)
        accessOrder.append(key)
        currentBytes += size
    }

    private func estimateSize(_ image: NSImage) -> Int {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)
        return w * h * 4 // RGBA
    }
}
```

**Step 2: Wire into MockPDFService**

Add a `RenderCache` instance and use it in `renderPage()` to cache by `"\(path):\(page):\(dpi)"`.

**Step 3: Build and test**

Run: `xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/RenderCache.swift PdfDiffApp/PdfDiff/Services/MockPDFService.swift
git commit -m "feat: add LRU render cache with 500MB cap"
```

---

### Task 19: Edge Case Handling

Graceful handling of problematic PDFs.

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/BatchViewModel.swift`

**Step 1: Add error handling for large PDFs**

In InspectorViewModel, add a page count check in `loadDocument()`:

```swift
        if doc.pageCount > 100 {
            // Warn but don't block
            errorMessage = "Large document (\(doc.pageCount) pages). Navigation may be slow."
        }
```

**Step 2: Handle encrypted PDFs**

In document loading paths, catch password-protected errors and show a clear user message rather than a generic error.

**Step 3: Handle corrupted files gracefully**

Wrap rendering and preflight calls in do/catch blocks that show partial results rather than failing completely.

**Step 4: Build and test**

Run: `xcodebuild -project PdfDiffApp/PdfDiff.xcodeproj -scheme PdfDiff build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/
git commit -m "fix: add edge case handling for large, encrypted, and corrupted PDFs"
```

---

## Task Dependency Summary

```
Phase 1: Rust Preflight          Phase 2: Swift Preflight       Phase 3: Barcodes
┌──────────────┐                ┌──────────────┐               ┌──────────────┐
│ T1: Types    │───────────────▶│ T5: Models   │               │ T9: Service  │
│ T2: Ink cov  │               │ T6: Service  │               │ T10: Wire UI │
│ T3: Page chk │               │ T7: Panel UI │               └──────┬───────┘
│ T4: UniFFI   │───────────────▶│ T8: Wire VM  │◀──────────────────────┘
└──────────────┘                └──────┬───────┘
                                       │
Phase 4: Separations            Phase 5: Reports               Phase 6: Batch
┌──────────────┐                ┌──────────────┐               ┌──────────────┐
│ T11: Rust    │                │ T13: Service │◀──────────────│ T15: Model   │
│ T12: UI      │                │ T14: UI      │               │ T16: UI      │
└──────────────┘                └──────┬───────┘               └──────────────┘
                                       │
                                Phase 7: Polish
                                ┌──────────────┐
                                │ T17: AI narr │
                                │ T18: LRU     │
                                │ T19: Edge    │
                                └──────────────┘
```

Phases 1-2 must be sequential. Phases 3, 4 can run in parallel after Phase 2. Phase 5 depends on models from Phases 2-3. Phase 6 is independent. Phase 7 ties everything together.
