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

    fn render_page(&self, page: u32, dpi: u32, colorspace: &RenderColorspace) -> Result<RenderedPage, PdfError> {
        let total = self.page_count();
        if page >= total {
            return Err(PdfError::PageOutOfRange { requested: page, total });
        }

        let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let scale = dpi as f32 / 72.0;
        let matrix = mupdf::Matrix::new_scale(scale, scale);

        let cs = match colorspace {
            RenderColorspace::Rgb => mupdf::Colorspace::device_rgb(),
            RenderColorspace::Cmyk => mupdf::Colorspace::device_cmyk(),
        };

        let pixmap = pdf_page.to_pixmap(&matrix, &cs, true, true).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let width = pixmap.width();
        let height = pixmap.height();
        let samples = pixmap.samples().to_vec();

        Ok(RenderedPage {
            bitmap: samples,
            width,
            height,
            colorspace: colorspace.clone(),
        })
    }

    fn pages_metadata(&self) -> Result<Vec<PageMetadata>, PdfError> {
        let count = self.page_count();
        let mut pages = Vec::with_capacity(count as usize);

        for i in 0..count {
            let page = self.doc.load_page(i as i32).map_err(|e| {
                PdfError::RenderingFailed { detail: e.to_string() }
            })?;

            let bounds = page.bounds().map_err(|e| {
                PdfError::RenderingFailed { detail: e.to_string() }
            })?;

            let width_pt = (bounds.x1 - bounds.x0) as f64;
            let height_pt = (bounds.y1 - bounds.y0) as f64;

            pages.push(PageMetadata {
                page_number: i,
                width_pt,
                height_pt,
                rotation: 0, // MuPDF applies rotation during rendering
                has_transparency: false,
                colorspaces_used: Vec::new(),
                font_names: Vec::new(), // Font enumeration requires deeper MuPDF access
                image_count: 0,
            });
        }

        Ok(pages)
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
