use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::InkCoverageResult;

/// Computes ink coverage for a page by rendering in CMYK and analyzing channel values.
/// Implemented in Task 2.
pub fn compute_ink_coverage(
    _doc: &dyn PdfDocumentHandle,
    _page: u32,
    _dpi: u32,
) -> Result<InkCoverageResult, PdfError> {
    Err(PdfError::RenderingFailed {
        detail: "Not yet implemented".to_string(),
    })
}
