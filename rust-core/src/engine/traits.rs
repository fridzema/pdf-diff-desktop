use crate::error::PdfError;
use crate::types::*;

pub trait PdfEngine: Send + Sync {
    fn open(&self, path: &str) -> Result<Box<dyn PdfDocumentHandle>, PdfError>;
}

pub trait PdfDocumentHandle: Send + Sync {
    fn page_count(&self) -> u32;
    fn render_page(&self, page: u32, dpi: u32, colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError>;
    fn metadata(&self) -> Result<DocumentMetadata, PdfError>;
    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError>;
    fn layers(&self) -> Result<Vec<Layer>, PdfError>;
    fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError>;
    fn render_separation(&self, page: u32, separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError>;
    fn extract_page_text(&self, page: u32) -> Result<String, PdfError>;
}
