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
    // RGB at 72 DPI with alpha: 4 bytes per pixel (RGBA)
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
