use std::path::PathBuf;

pub fn fixture_path(name: &str) -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("..");
    path.push("fixtures");
    path.push(name);
    path
}

/// Creates a simple 1-page PDF at the given path using printpdf 0.8
pub fn create_simple_pdf(path: &std::path::Path) {
    use printpdf::*;

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }

    let page = PdfPage::new(Mm(210.0), Mm(297.0), vec![
        Op::StartTextSection,
        Op::SetFontSizeBuiltinFont { size: Pt(48.0), font: BuiltinFont::Helvetica },
        Op::SetTextCursor { pos: Point { x: Mm(10.0).into(), y: Mm(270.0).into() } },
        Op::WriteTextBuiltinFont {
            items: vec![TextItem::Text("Hello World".to_string())],
            font: BuiltinFont::Helvetica,
        },
        Op::EndTextSection,
    ]);

    let mut doc = PdfDocument::new("Test Document");
    doc.with_pages(vec![page]);

    let mut warnings = Vec::new();
    let bytes = doc.save(&PdfSaveOptions::default(), &mut warnings);
    std::fs::write(path, bytes).unwrap();
}
