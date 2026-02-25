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
