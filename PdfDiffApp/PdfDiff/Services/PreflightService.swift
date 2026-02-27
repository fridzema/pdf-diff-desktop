import Foundation
import PDFKit

final class PreflightService: @unchecked Sendable {

    /// Check page boxes using PDFKit (BleedBox, TrimBox, MediaBox).
    func checkPageBoxes(pdfPath: String) -> [PreflightCheckItem] {
        guard let pdfDoc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            return [PreflightCheckItem(
                category: .pageBoxes, severity: .fail,
                title: "Cannot open PDF", detail: "Failed to open \(pdfPath)", page: nil
            )]
        }

        var checks: [PreflightCheckItem] = []
        for i in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }
            let pageNum = UInt32(i)

            let mediaBox = page.bounds(for: .mediaBox)
            let trimBox = page.bounds(for: .trimBox)
            let bleedBox = page.bounds(for: .bleedBox)

            // Check if trim box is defined (different from media box)
            let hasTrimBox = trimBox != mediaBox
            // Check if bleed box is defined and extends beyond trim
            let hasBleedBox = bleedBox != mediaBox && bleedBox != trimBox

            if hasBleedBox {
                // Check minimum bleed (3mm = ~8.5 points)
                let referenceBox = hasTrimBox ? trimBox : mediaBox
                let bleedLeft = referenceBox.minX - bleedBox.minX
                let bleedRight = bleedBox.maxX - referenceBox.maxX
                let bleedTop = bleedBox.maxY - referenceBox.maxY
                let bleedBottom = referenceBox.minY - bleedBox.minY
                let minBleed = min(bleedLeft, bleedRight, bleedTop, bleedBottom)
                let minBleedMM = minBleed * 25.4 / 72.0
                if minBleedMM < 3.0 {
                    checks.append(PreflightCheckItem(
                        category: .pageBoxes, severity: .warn,
                        title: "Page \(i + 1): Insufficient bleed",
                        detail: String(format: "Minimum bleed: %.1fmm (recommended: 3mm+)", minBleedMM),
                        page: pageNum
                    ))
                }
            } else {
                checks.append(PreflightCheckItem(
                    category: .pageBoxes, severity: .fail,
                    title: "Page \(i + 1): No bleed defined",
                    detail: "BleedBox equals \(hasTrimBox ? "TrimBox" : "MediaBox"). Add 3mm+ bleed for print.",
                    page: pageNum
                ))
            }

            if !hasTrimBox && !hasBleedBox {
                checks.append(PreflightCheckItem(
                    category: .pageBoxes, severity: .info,
                    title: "Page \(i + 1): Only MediaBox defined",
                    detail: String(format: "MediaBox: %.0f x %.0f pt. No TrimBox or BleedBox set.",
                                   mediaBox.width, mediaBox.height),
                    page: pageNum
                ))
            }
        }

        if checks.isEmpty {
            checks.append(PreflightCheckItem(
                category: .pageBoxes, severity: .pass,
                title: "Page boxes OK",
                detail: "All pages have proper TrimBox and BleedBox defined.",
                page: nil
            ))
        }

        return checks
    }

    /// Merge Rust-side and Swift-side preflight results into one.
    static func mergeResults(
        rustChecks: [PreflightCheckItem],
        swiftChecks: [PreflightCheckItem]
    ) -> SwiftPreflightResult {
        SwiftPreflightResult(checks: rustChecks + swiftChecks)
    }
}
