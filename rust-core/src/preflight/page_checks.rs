use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{PreflightCheck, PreflightCategory, PreflightSeverity};

/// Checks that all pages have consistent dimensions and orientation.
pub fn check_page_consistency(
    doc: &dyn PdfDocumentHandle,
) -> Result<Vec<PreflightCheck>, PdfError> {
    let pages = doc.pages_metadata()?;
    let mut checks = Vec::new();

    if pages.is_empty() {
        checks.push(PreflightCheck {
            category: PreflightCategory::PageConsistency,
            severity: PreflightSeverity::Warn,
            title: "No pages".to_string(),
            detail: "Document has no pages".to_string(),
            page: None,
        });
        return Ok(checks);
    }

    let first = &pages[0];
    let ref_width = first.width_pt;
    let ref_height = first.height_pt;
    let ref_landscape = ref_width > ref_height;
    let mut all_consistent = true;

    for p in pages.iter().skip(1) {
        let size_match = (p.width_pt - ref_width).abs() < 0.5
            && (p.height_pt - ref_height).abs() < 0.5;
        let landscape = p.width_pt > p.height_pt;

        if !size_match {
            all_consistent = false;
            checks.push(PreflightCheck {
                category: PreflightCategory::PageConsistency,
                severity: PreflightSeverity::Warn,
                title: format!("Page {} size mismatch", p.page_number + 1),
                detail: format!(
                    "Page {} is {:.1} x {:.1} pt, expected {:.1} x {:.1} pt",
                    p.page_number + 1, p.width_pt, p.height_pt, ref_width, ref_height
                ),
                page: Some(p.page_number),
            });
        }

        if landscape != ref_landscape {
            all_consistent = false;
            checks.push(PreflightCheck {
                category: PreflightCategory::PageConsistency,
                severity: PreflightSeverity::Warn,
                title: format!("Page {} orientation mismatch", p.page_number + 1),
                detail: format!(
                    "Page {} is {}, expected {}",
                    p.page_number + 1,
                    if landscape { "landscape" } else { "portrait" },
                    if ref_landscape { "landscape" } else { "portrait" }
                ),
                page: Some(p.page_number),
            });
        }
    }

    if all_consistent {
        checks.push(PreflightCheck {
            category: PreflightCategory::PageConsistency,
            severity: PreflightSeverity::Pass,
            title: "Page sizes consistent".to_string(),
            detail: format!("{} pages, all {:.1} x {:.1} pt", pages.len(), ref_width, ref_height),
            page: None,
        });
    }

    Ok(checks)
}
