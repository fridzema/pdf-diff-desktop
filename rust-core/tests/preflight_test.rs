mod helpers;

use pdf_diff_core::engine::mupdf_engine::MuPdfEngine;
use pdf_diff_core::engine::traits::PdfEngine;
use pdf_diff_core::preflight::ink_coverage::compute_ink_coverage;
use pdf_diff_core::preflight::page_checks::check_page_consistency;
use pdf_diff_core::types::PreflightSeverity;

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

use pdf_diff_core::preflight::separations::extract_cmyk_channels;
use pdf_diff_core::preflight::run_preflight;

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
