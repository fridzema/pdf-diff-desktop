use rayon::prelude::*;

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
/// Uses rayon for parallel processing of pixel rows.
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
    let row_bytes = (width * bytes_per_pixel) as usize;

    // Track bounding boxes of changed regions using a simple grid
    let grid_size = 32u32;
    let grid_w = (width + grid_size - 1) / grid_size;
    let grid_h = (height + grid_size - 1) / grid_size;

    // Process rows in parallel using rayon
    let row_results: Vec<(Vec<u8>, u64, Vec<(u32, u32)>)> = (0..height)
        .into_par_iter()
        .map(|y| {
            let row_start = (y * width * bytes_per_pixel) as usize;
            let row_end = row_start + row_bytes;

            // Bounds check
            if row_end > left.len() || row_end > right.len() {
                return (vec![0u8; row_bytes], 0u64, Vec::new());
            }

            let left_row = &left[row_start..row_end];
            let right_row = &right[row_start..row_end];
            let mut diff_row = vec![0u8; row_bytes];
            let mut row_changed: u64 = 0;
            let mut grid_hits: Vec<(u32, u32)> = Vec::new();

            for x in 0..width {
                let idx = (x * bytes_per_pixel) as usize;
                if idx + 3 >= row_bytes {
                    break;
                }

                let dr = (left_row[idx] as i16 - right_row[idx] as i16).unsigned_abs();
                let dg = (left_row[idx + 1] as i16 - right_row[idx + 1] as i16).unsigned_abs();
                let db = (left_row[idx + 2] as i16 - right_row[idx + 2] as i16).unsigned_abs();
                let max_diff = dr.max(dg).max(db);

                if max_diff > threshold {
                    row_changed += 1;
                    diff_row[idx] = 255;     // R
                    diff_row[idx + 1] = 0;   // G
                    diff_row[idx + 2] = 0;   // B
                    diff_row[idx + 3] = 180; // A

                    let gx = x / grid_size;
                    let gy = y / grid_size;
                    grid_hits.push((gx, gy));
                } else {
                    diff_row[idx] = left_row[idx] / 3;
                    diff_row[idx + 1] = left_row[idx + 1] / 3;
                    diff_row[idx + 2] = left_row[idx + 2] / 3;
                    diff_row[idx + 3] = 255;
                }
            }

            (diff_row, row_changed, grid_hits)
        })
        .collect();

    // Merge results
    let mut diff_bitmap = Vec::with_capacity(left.len());
    let mut changed_pixel_count: u64 = 0;
    let mut grid_changed = vec![false; (grid_w * grid_h) as usize];

    for (diff_row, row_changed, grid_hits) in row_results {
        diff_bitmap.extend_from_slice(&diff_row);
        changed_pixel_count += row_changed;
        for (gx, gy) in grid_hits {
            grid_changed[(gy * grid_w + gx) as usize] = true;
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
