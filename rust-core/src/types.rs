use uniffi;

#[derive(Debug, Clone, uniffi::Enum)]
pub enum RenderColorspace {
    Rgb,
    Cmyk,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum LayerType {
    View,
    Print,
    Export,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum ReportFormat {
    Pdf,
    Html,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct RenderedPage {
    pub bitmap: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub colorspace: RenderColorspace,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DocumentMetadata {
    pub title: Option<String>,
    pub author: Option<String>,
    pub creator: Option<String>,
    pub producer: Option<String>,
    pub creation_date: Option<String>,
    pub modification_date: Option<String>,
    pub pdf_version: String,
    pub page_count: u32,
    pub file_size_bytes: u64,
    pub is_linearized: bool,
    pub is_encrypted: bool,
    pub color_profiles: Vec<ColorProfile>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ColorProfile {
    pub name: String,
    pub colorspace: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PageMetadata {
    pub page_number: u32,
    pub width_pt: f64,
    pub height_pt: f64,
    pub rotation: u32,
    pub has_transparency: bool,
    pub colorspaces_used: Vec<String>,
    pub font_names: Vec<String>,
    pub image_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Layer {
    pub name: String,
    pub is_visible: bool,
    pub layer_type: LayerType,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Separation {
    pub name: String,
    pub colorspace: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DiffResult {
    pub similarity_score: f64,
    pub diff_bitmap: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub changed_regions: Vec<DiffRegion>,
    pub changed_pixel_count: u64,
    pub total_pixel_count: u64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DiffRegion {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct StructuralDiffResult {
    pub metadata_changes: Vec<MetadataChange>,
    pub text_changes: Vec<TextChange>,
    pub font_changes: Vec<FontChange>,
    pub page_size_changes: Vec<PageSizeChange>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct MetadataChange {
    pub field: String,
    pub left_value: Option<String>,
    pub right_value: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TextChange {
    pub page: u32,
    pub left_text: String,
    pub right_text: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FontChange {
    pub page: u32,
    pub left_fonts: Vec<String>,
    pub right_fonts: Vec<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct PageSizeChange {
    pub page: u32,
    pub left_width: f64,
    pub left_height: f64,
    pub right_width: f64,
    pub right_height: f64,
}
