use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::*;

pub fn compute_structural_diff(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<StructuralDiffResult, PdfError> {
    let metadata_changes = diff_metadata(left, right)?;
    let (text_changes, font_changes) = diff_pages_content(left, right)?;
    let page_size_changes = diff_page_sizes(left, right)?;

    Ok(StructuralDiffResult {
        metadata_changes,
        text_changes,
        font_changes,
        page_size_changes,
    })
}

fn diff_metadata(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<Vec<MetadataChange>, PdfError> {
    let lm = left.metadata()?;
    let rm = right.metadata()?;
    let mut changes = Vec::new();

    let fields = [
        ("title", lm.title.clone(), rm.title.clone()),
        ("author", lm.author.clone(), rm.author.clone()),
        ("creator", lm.creator.clone(), rm.creator.clone()),
        ("producer", lm.producer.clone(), rm.producer.clone()),
        ("pdf_version", Some(lm.pdf_version.clone()), Some(rm.pdf_version.clone())),
    ];

    for (field, lv, rv) in fields {
        if lv != rv {
            changes.push(MetadataChange {
                field: field.to_string(),
                left_value: lv,
                right_value: rv,
            });
        }
    }

    Ok(changes)
}

fn diff_pages_content(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<(Vec<TextChange>, Vec<FontChange>), PdfError> {
    let left_count = left.page_count();
    let right_count = right.page_count();
    let compare_count = left_count.min(right_count);

    let left_pages = left.pages_metadata()?;
    let right_pages = right.pages_metadata()?;

    let mut text_changes = Vec::new();
    let mut font_changes = Vec::new();

    for page in 0..compare_count {
        let left_text = left.extract_page_text(page)?;
        let right_text = right.extract_page_text(page)?;

        if left_text != right_text {
            text_changes.push(TextChange {
                page,
                left_text,
                right_text,
            });
        }

        if (page as usize) < left_pages.len() && (page as usize) < right_pages.len() {
            let lf = &left_pages[page as usize].font_names;
            let rf = &right_pages[page as usize].font_names;
            if lf != rf {
                font_changes.push(FontChange {
                    page,
                    left_fonts: lf.clone(),
                    right_fonts: rf.clone(),
                });
            }
        }
    }

    Ok((text_changes, font_changes))
}

fn diff_page_sizes(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
) -> Result<Vec<PageSizeChange>, PdfError> {
    let lp = left.pages_metadata()?;
    let rp = right.pages_metadata()?;
    let compare_count = lp.len().min(rp.len());
    let mut changes = Vec::new();

    for i in 0..compare_count {
        let l = &lp[i];
        let r = &rp[i];
        if (l.width_pt - r.width_pt).abs() > 0.01 || (l.height_pt - r.height_pt).abs() > 0.01 {
            changes.push(PageSizeChange {
                page: i as u32,
                left_width: l.width_pt,
                left_height: l.height_pt,
                right_width: r.width_pt,
                right_height: r.height_pt,
            });
        }
    }

    Ok(changes)
}
