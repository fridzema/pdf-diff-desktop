import Testing
import AppKit
@testable import PdfDiff

@Suite("ReportGenerator Tests")
struct ReportGeneratorTests {

    @Test("markdown report for inspection")
    func markdownInspectionReport() {
        let preflight = SwiftPreflightResult(checks: [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "Ink OK", detail: "Max 220%", page: nil),
            PreflightCheckItem(category: .pageBoxes, severity: .warn, title: "No bleed", detail: "Page 1", page: 0),
        ])
        let generator = ReportGenerator()
        let markdown = generator.generateMarkdown(
            documentName: "test.pdf",
            preflight: preflight,
            barcodes: [],
            inspection: nil,
            aiNarrative: nil
        )
        #expect(markdown.contains("test.pdf"))
        #expect(markdown.contains("Ink OK"))
        #expect(markdown.contains("No bleed"))
        #expect(markdown.contains("Preflight"))
    }

    @Test("markdown includes barcodes")
    func markdownWithBarcodes() {
        let barcodes = [
            DetectedBarcode(symbology: "EAN13", payload: "123456", boundingBox: .zero, confidence: 1.0)
        ]
        let generator = ReportGenerator()
        let markdown = generator.generateMarkdown(
            documentName: "test.pdf",
            preflight: SwiftPreflightResult(checks: []),
            barcodes: barcodes,
            inspection: nil,
            aiNarrative: nil
        )
        #expect(markdown.contains("123456"))
        #expect(markdown.contains("EAN13"))
    }
}
