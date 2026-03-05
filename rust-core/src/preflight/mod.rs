pub mod ink_coverage;
pub mod page_checks;
pub mod separations;

use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::{PreflightResult, PreflightSummary, PreflightCheck, PreflightSeverity,
                   PreflightCategory, RenderColorspace};

/// Runs all Rust-side preflight checks on a document.
/// `dpi`: Resolution for rendering-based checks (72 is fine for ink coverage).
/// `max_ink_limit`: Maximum total ink percentage before warning (typically 300.0).
pub fn run_preflight(
    doc: &dyn PdfDocumentHandle,
    dpi: u32,
    max_ink_limit: f64,
) -> Result<PreflightResult, PdfError> {
    let mut checks = Vec::new();

    // Page consistency
    checks.extend(page_checks::check_page_consistency(doc)?);

    // Ink coverage (per page, cap at 10 pages for speed)
    // Render CMYK once per page and reuse for both ink coverage and separations
    let page_count = doc.page_count();
    for page in 0..page_count.min(10) {
        match doc.render_page(page, dpi, &RenderColorspace::Cmyk) {
            Ok(rendered) => {
                match ink_coverage::compute_ink_coverage_from_bitmap(
                    &rendered.bitmap, rendered.width, rendered.height, page
                ) {
                    Ok(ink) => {
                        let severity = if ink.total > max_ink_limit + 40.0 {
                            PreflightSeverity::Fail
                        } else if ink.total > max_ink_limit {
                            PreflightSeverity::Warn
                        } else {
                            PreflightSeverity::Pass
                        };

                        checks.push(PreflightCheck {
                            category: PreflightCategory::InkCoverage,
                            severity,
                            title: format!("Page {} ink coverage", page + 1),
                            detail: format!(
                                "C:{:.1}% M:{:.1}% Y:{:.1}% K:{:.1}% — Max total: {:.1}%",
                                ink.cyan, ink.magenta, ink.yellow, ink.black, ink.total
                            ),
                            page: Some(page),
                        });
                    }
                    Err(e) => {
                        checks.push(PreflightCheck {
                            category: PreflightCategory::InkCoverage,
                            severity: PreflightSeverity::Warn,
                            title: format!("Page {} ink coverage failed", page + 1),
                            detail: e.to_string(),
                            page: Some(page),
                        });
                    }
                }
            }
            Err(e) => {
                checks.push(PreflightCheck {
                    category: PreflightCategory::InkCoverage,
                    severity: PreflightSeverity::Warn,
                    title: format!("Page {} ink coverage failed", page + 1),
                    detail: e.to_string(),
                    page: Some(page),
                });
            }
        }
    }

    let summary = compute_summary(&checks);
    Ok(PreflightResult { checks, summary })
}

fn compute_summary(checks: &[PreflightCheck]) -> PreflightSummary {
    let mut pass = 0u32;
    let mut warn = 0u32;
    let mut fail = 0u32;
    let mut info = 0u32;
    for c in checks {
        match c.severity {
            PreflightSeverity::Pass => pass += 1,
            PreflightSeverity::Warn => warn += 1,
            PreflightSeverity::Fail => fail += 1,
            PreflightSeverity::Info => info += 1,
        }
    }
    PreflightSummary {
        pass_count: pass,
        warn_count: warn,
        fail_count: fail,
        info_count: info,
    }
}
