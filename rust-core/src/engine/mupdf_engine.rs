use mupdf::{Document, MetadataName};
use crate::engine::traits::{PdfEngine, PdfDocumentHandle};
use crate::error::PdfError;
use crate::types::*;

pub struct MuPdfEngine;

impl MuPdfEngine {
    pub fn new() -> Self {
        Self
    }
}

impl PdfEngine for MuPdfEngine {
    fn open(&self, path: &str) -> Result<Box<dyn PdfDocumentHandle>, PdfError> {
        if !std::path::Path::new(path).exists() {
            return Err(PdfError::FileNotFound { path: path.to_string() });
        }

        let doc = Document::open(path).map_err(|e| {
            let msg = e.to_string();
            if msg.contains("password") {
                PdfError::PasswordProtected
            } else {
                PdfError::InvalidPdf { detail: msg }
            }
        })?;

        let file_size = std::fs::metadata(path)
            .map(|m| m.len())
            .unwrap_or(0);

        Ok(Box::new(MuPdfDocument {
            doc,
            _path: path.to_string(),
            file_size,
        }))
    }
}

struct MuPdfDocument {
    doc: Document,
    _path: String,
    file_size: u64,
}

// MuPDF Document is not Send/Sync by default, but we only access it
// from one thread at a time (Swift dispatches to background serially).
// This unsafe impl is required for the trait bound.
unsafe impl Send for MuPdfDocument {}
unsafe impl Sync for MuPdfDocument {}

impl PdfDocumentHandle for MuPdfDocument {
    fn page_count(&self) -> u32 {
        self.doc.page_count().unwrap_or(0) as u32
    }

    fn metadata(&self) -> Result<DocumentMetadata, PdfError> {
        let meta_field = |name: MetadataName| -> Option<String> {
            self.doc.metadata(name).ok().filter(|s| !s.is_empty())
        };

        Ok(DocumentMetadata {
            title: meta_field(MetadataName::Title),
            author: meta_field(MetadataName::Author),
            creator: meta_field(MetadataName::Creator),
            producer: meta_field(MetadataName::Producer),
            creation_date: meta_field(MetadataName::CreationDate),
            modification_date: meta_field(MetadataName::ModDate),
            pdf_version: meta_field(MetadataName::Format).unwrap_or_else(|| "unknown".to_string()),
            page_count: self.page_count(),
            file_size_bytes: self.file_size,
            is_linearized: false, // MuPDF doesn't expose this easily
            is_encrypted: self.doc.needs_password().unwrap_or(false),
            color_profiles: Vec::new(), // Populated later via mupdf-sys FFI
        })
    }

    fn render_page(&self, _page: u32, _dpi: u32, _colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError> {
        todo!("Implemented in Task 4")
    }

    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError> {
        todo!("Implemented in Task 4")
    }

    fn layers(&self) -> Result<Vec<Layer>, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn separations(&self, _page: u32) -> Result<Vec<Separation>, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn render_separation(&self, _page: u32, _separation_index: u32, _dpi: u32) -> Result<RenderedPage, PdfError> {
        todo!("Implemented in Task 5")
    }

    fn extract_page_text(&self, _page: u32) -> Result<String, PdfError> {
        todo!("Implemented in Task 6")
    }
}
