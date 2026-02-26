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
