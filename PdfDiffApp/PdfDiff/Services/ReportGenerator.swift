import Foundation
import AppKit
import PDFKit

final class ReportGenerator {

    // MARK: - Markdown Report

    func generateMarkdown(
        documentName: String,
        preflight: SwiftPreflightResult?,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?,
        aiNarrative: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# QC Report: \(documentName)")
        lines.append("")
        lines.append("**Generated:** \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        // AI Narrative (if available)
        if let narrative = aiNarrative, !narrative.isEmpty {
            lines.append("## Summary")
            lines.append(narrative)
            lines.append("")
        }

        // Preflight Results
        if let preflight = preflight, !preflight.checks.isEmpty {
            lines.append("## Preflight Results")
            lines.append("")
            let s = preflight.summary
            lines.append("| Status | Count |")
            lines.append("|--------|-------|")
            if s.passCount > 0 { lines.append("| Pass | \(s.passCount) |") }
            if s.warnCount > 0 { lines.append("| Warning | \(s.warnCount) |") }
            if s.failCount > 0 { lines.append("| Fail | \(s.failCount) |") }
            if s.infoCount > 0 { lines.append("| Info | \(s.infoCount) |") }
            lines.append("")

            for group in preflight.groupedByCategory {
                lines.append("### \(group.category.displayName)")
                for check in group.checks {
                    let icon = severityIcon(check.severity)
                    lines.append("- \(icon) **\(check.title)**")
                    if !check.detail.isEmpty {
                        lines.append("  \(check.detail)")
                    }
                }
                lines.append("")
            }
        }

        // Barcodes
        if !barcodes.isEmpty {
            lines.append("## Barcodes Detected")
            lines.append("")
            lines.append("| Type | Data |")
            lines.append("|------|------|")
            for barcode in barcodes {
                lines.append("| \(barcode.displaySymbology) | `\(barcode.payload)` |")
            }
            lines.append("")
        }

        // AI Inspection
        if let inspection = inspection {
            lines.append("## AI Inspection")
            lines.append("")
            lines.append(inspection.summary)
            lines.append("")
            for issue in inspection.issues {
                let icon = issue.severity == .fail ? "FAIL" : issue.severity == .warn ? "WARN" : "PASS"
                lines.append("- [\(icon)] **\(issue.title)**: \(issue.detail)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - PDF Report

    func generatePDF(
        documentName: String,
        preflight: SwiftPreflightResult?,
        barcodes: [DetectedBarcode],
        inspection: InspectionResult?,
        aiNarrative: String?,
        pageImage: NSImage?
    ) -> Data? {
        let markdown = generateMarkdown(
            documentName: documentName,
            preflight: preflight,
            barcodes: barcodes,
            inspection: inspection,
            aiNarrative: aiNarrative
        )

        // Use NSAttributedString to create a simple PDF from the markdown text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]
        let attrStr = NSAttributedString(string: markdown, attributes: attrs)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
            height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        ))
        textView.textStorage?.setAttributedString(attrStr)

        let data = textView.dataWithPDF(inside: textView.bounds)
        return data
    }

    private func severityIcon(_ severity: PreflightCheckSeverity) -> String {
        switch severity {
        case .pass: return "PASS"
        case .warn: return "WARN"
        case .fail: return "FAIL"
        case .info: return "INFO"
        }
    }
}
