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
    assert!(result.total <= 100.0, "Total should be <= 100%: {}", result.total);
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
