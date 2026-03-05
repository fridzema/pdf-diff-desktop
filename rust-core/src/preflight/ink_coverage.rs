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
    compute_ink_coverage_from_bitmap(&rendered.bitmap, rendered.width, rendered.height, page)
}

/// Computes ink coverage from a pre-rendered CMYK bitmap.
/// Avoids redundant rendering when the bitmap is already available.
pub fn compute_ink_coverage_from_bitmap(
    bitmap: &[u8],
    width: u32,
    height: u32,
    page: u32,
) -> Result<InkCoverageResult, PdfError> {
    let pixel_count = (width * height) as usize;
    if pixel_count == 0 {
        return Err(PdfError::RenderingFailed {
            detail: "Empty rendered page".to_string(),
        });
    }

    // MuPDF CMYK pixmap with alpha: 5 bytes per pixel (C, M, Y, K, A)
    // Without alpha: 4 bytes per pixel (C, M, Y, K)
    let bytes_per_pixel = bitmap.len() / pixel_count;
    if bytes_per_pixel < 4 {
        return Err(PdfError::RenderingFailed {
            detail: format!(
                "CMYK bitmap size mismatch: {} bytes for {} pixels ({} bpp)",
                bitmap.len(), pixel_count, bytes_per_pixel
            ),
        });
    }

    let mut sum_c: f64 = 0.0;
    let mut sum_m: f64 = 0.0;
    let mut sum_y: f64 = 0.0;
    let mut sum_k: f64 = 0.0;
    let mut max_total: f64 = 0.0;

    for i in 0..pixel_count {
        let offset = i * bytes_per_pixel;
        let c = bitmap[offset] as f64 / 255.0 * 100.0;
        let m = bitmap[offset + 1] as f64 / 255.0 * 100.0;
        let y = bitmap[offset + 2] as f64 / 255.0 * 100.0;
        let k = bitmap[offset + 3] as f64 / 255.0 * 100.0;
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
