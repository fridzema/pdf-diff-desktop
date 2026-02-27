pub mod diff;
pub mod engine;
pub mod error;
pub mod preflight;
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
pub fn compute_pixel_diff_uniffi(
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
pub fn compute_structural_diff_uniffi(
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
