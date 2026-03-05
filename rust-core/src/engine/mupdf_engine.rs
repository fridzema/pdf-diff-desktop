use std::cell::RefCell;
use std::num::NonZeroUsize;
use lru::LruCache;
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
            render_cache: RefCell::new(LruCache::new(NonZeroUsize::new(20).unwrap())),
        }))
    }
}

struct MuPdfDocument {
    doc: Document,
    _path: String,
    file_size: u64,
    render_cache: RefCell<LruCache<(u32, u32, RenderColorspace), RenderedPage>>,
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

        let cache_key = (page, dpi, colorspace.clone());

        // Check cache first
        {
            let mut cache = self.render_cache.borrow_mut();
            if let Some(cached) = cache.get(&cache_key) {
                return Ok(cached.clone());
            }
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

        let result = RenderedPage {
            bitmap: samples,
            width,
            height,
            colorspace: colorspace.clone(),
        };

        // Store in cache
        self.render_cache.borrow_mut().put(cache_key, result.clone());

        Ok(result)
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
        // MuPDF safe API does not expose OCG layers directly.
        // Full implementation requires mupdf-sys FFI calls to:
        //   pdf_count_layer_configs, pdf_layer_config_ui, etc.
        // For now, return empty. Will be enhanced with mupdf-sys wrappers.
        Ok(Vec::new())
    }

    fn separations(&self, page: u32) -> Result<Vec<Separation>, PdfError> {
        let total = self.page_count();
        if page >= total {
            return Err(PdfError::PageOutOfRange { requested: page, total });
        }

        let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let seps = pdf_page.separations().map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        // The safe mupdf API exposes Separations with len() and active_count()
        // but NOT individual names. Full implementation needs mupdf-sys FFI.
        let count = seps.len();
        let mut result = Vec::new();
        for i in 0..count {
            result.push(Separation {
                name: format!("Separation {}", i),
                colorspace: "Unknown".to_string(),
            });
        }

        Ok(result)
    }

    fn render_separation(&self, page: u32, _separation_index: u32, dpi: u32) -> Result<RenderedPage, PdfError> {
        // Full separation rendering requires mupdf-sys FFI:
        //   fz_new_pixmap_from_page_contents_with_separations
        // For now, render the full page as a fallback.
        self.render_page(page, dpi, &RenderColorspace::Cmyk)
    }

    fn extract_page_text(&self, page: u32) -> Result<String, PdfError> {
        let total = self.page_count();
        if page >= total {
            return Err(PdfError::PageOutOfRange { requested: page, total });
        }

        let pdf_page = self.doc.load_page(page as i32).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        let text_page = pdf_page.to_text_page(mupdf::TextPageFlags::empty()).map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })?;

        text_page.to_text().map_err(|e| {
            PdfError::RenderingFailed { detail: e.to_string() }
        })
    }
}
