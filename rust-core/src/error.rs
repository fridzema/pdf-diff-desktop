use uniffi;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PdfError {
    #[error("File not found: {path}")]
    FileNotFound { path: String },
    #[error("Invalid PDF: {detail}")]
    InvalidPdf { detail: String },
    #[error("PDF is password protected")]
    PasswordProtected,
    #[error("Page {requested} out of range (total: {total})")]
    PageOutOfRange { requested: u32, total: u32 },
    #[error("Rendering failed: {detail}")]
    RenderingFailed { detail: String },
    #[error("Unsupported colorspace: {name}")]
    UnsupportedColorspace { name: String },
    #[error("Page count mismatch: left={left}, right={right}")]
    DiffPageCountMismatch { left: u32, right: u32 },
    #[error("Page size mismatch on page {page}")]
    DiffPageSizeMismatch { page: u32 },
    #[error("Report generation failed: {detail}")]
    ReportGenerationFailed { detail: String },
    #[error("Internal error: {detail}")]
    InternalError { detail: String },
}
