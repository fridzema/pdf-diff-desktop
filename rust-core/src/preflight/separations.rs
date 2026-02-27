use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::RenderColorspace;

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
