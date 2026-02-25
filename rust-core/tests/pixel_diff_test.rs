mod helpers;

use pdf_diff_core::diff::pixel::{compute_pixel_diff_from_bitmaps, compute_pixel_diff};
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
    let bitmap_a = vec![128u8; 10 * 10 * 4];
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
