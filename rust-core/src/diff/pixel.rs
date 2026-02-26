use crate::engine::traits::PdfDocumentHandle;
use crate::error::PdfError;
use crate::types::*;

/// Compute pixel diff between two rendered pages of two documents.
pub fn compute_pixel_diff(
    left: &dyn PdfDocumentHandle,
    right: &dyn PdfDocumentHandle,
    page: u32,
    dpi: u32,
    sensitivity: f32,
) -> Result<DiffResult, PdfError> {
    let cs = RenderColorspace::Rgb;
    let left_page = left.render_page(page, dpi, &cs)?;
    let right_page = right.render_page(page, dpi, &cs)?;

    Ok(compute_pixel_diff_from_bitmaps(
        &left_page.bitmap,
        &right_page.bitmap,
        left_page.width,
        left_page.height,
        sensitivity,
    ))
}

/// Pure bitmap comparison — no PDF dependency, fully unit-testable.
pub fn compute_pixel_diff_from_bitmaps(
    left: &[u8],
    right: &[u8],
    width: u32,
    height: u32,
    sensitivity: f32,
) -> DiffResult {
    let pixel_count = (width * height) as u64;
    let bytes_per_pixel = 4u32; // RGBA
    let threshold = (sensitivity * 255.0) as u16;

    let mut diff_bitmap = vec![0u8; left.len()];
    let mut changed_pixel_count: u64 = 0;

    // Track bounding boxes of changed regions using a simple grid
    let grid_size = 32u32;
    let grid_w = (width + grid_size - 1) / grid_size;
    let grid_h = (height + grid_size - 1) / grid_size;
    let mut grid_changed = vec![false; (grid_w * grid_h) as usize];

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * bytes_per_pixel) as usize;

            if idx + 3 >= left.len() || idx + 3 >= right.len() {
                break;
            }

            let dr = (left[idx] as i16 - right[idx] as i16).unsigned_abs();
            let dg = (left[idx + 1] as i16 - right[idx + 1] as i16).unsigned_abs();
            let db = (left[idx + 2] as i16 - right[idx + 2] as i16).unsigned_abs();
            let max_diff = dr.max(dg).max(db);

            if max_diff > threshold {
                changed_pixel_count += 1;
                // Mark diff pixel as red with semi-transparency
                diff_bitmap[idx] = 255;     // R
                diff_bitmap[idx + 1] = 0;   // G
                diff_bitmap[idx + 2] = 0;   // B
                diff_bitmap[idx + 3] = 180; // A

                let gx = x / grid_size;
                let gy = y / grid_size;
                grid_changed[(gy * grid_w + gx) as usize] = true;
            } else {
                // Unchanged pixel: dim version of original
                diff_bitmap[idx] = left[idx] / 3;
                diff_bitmap[idx + 1] = left[idx + 1] / 3;
                diff_bitmap[idx + 2] = left[idx + 2] / 3;
                diff_bitmap[idx + 3] = 255;
            }
        }
    }

    // Convert grid to bounding box regions
    let changed_regions = extract_regions(&grid_changed, grid_w, grid_h, grid_size);

    let similarity_score = if pixel_count == 0 {
        1.0
    } else {
        1.0 - (changed_pixel_count as f64 / pixel_count as f64)
    };

    DiffResult {
        similarity_score,
        diff_bitmap,
        width,
        height,
        changed_regions,
        changed_pixel_count,
        total_pixel_count: pixel_count,
    }
}

fn extract_regions(grid: &[bool], grid_w: u32, grid_h: u32, grid_size: u32) -> Vec<DiffRegion> {
    let mut regions = Vec::new();
    let mut visited = vec![false; grid.len()];

    for gy in 0..grid_h {
        for gx in 0..grid_w {
            let idx = (gy * grid_w + gx) as usize;
            if grid[idx] && !visited[idx] {
                // Flood-fill to find connected region
                let mut min_x = gx;
                let mut max_x = gx;
                let mut min_y = gy;
                let mut max_y = gy;
                let mut stack = vec![(gx, gy)];

                while let Some((cx, cy)) = stack.pop() {
                    let ci = (cy * grid_w + cx) as usize;
                    if visited[ci] || !grid[ci] {
                        continue;
                    }
                    visited[ci] = true;
                    min_x = min_x.min(cx);
                    max_x = max_x.max(cx);
                    min_y = min_y.min(cy);
                    max_y = max_y.max(cy);

                    if cx > 0 { stack.push((cx - 1, cy)); }
                    if cx < grid_w - 1 { stack.push((cx + 1, cy)); }
                    if cy > 0 { stack.push((cx, cy - 1)); }
                    if cy < grid_h - 1 { stack.push((cx, cy + 1)); }
                }

                regions.push(DiffRegion {
                    x: (min_x * grid_size) as f64,
                    y: (min_y * grid_size) as f64,
                    width: ((max_x - min_x + 1) * grid_size) as f64,
                    height: ((max_y - min_y + 1) * grid_size) as f64,
                });
            }
        }
    }

    regions
}
