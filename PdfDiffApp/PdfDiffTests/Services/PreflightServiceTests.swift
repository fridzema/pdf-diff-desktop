import Testing
import PDFKit
@testable import PdfDiff

@Suite("PreflightService Tests")
struct PreflightServiceTests {

    @Test("page box checks on nonexistent PDF")
    func pageBoxChecksNonexistent() {
        let service = PreflightService()
        let checks = service.checkPageBoxes(pdfPath: "/nonexistent.pdf")
        #expect(checks.first?.severity == .fail)
    }

    @Test("merge results combines Rust and Swift checks")
    func mergeResults() {
        let rustChecks = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "Ink OK", detail: "", page: nil),
        ]
        let swiftChecks = [
            PreflightCheckItem(category: .pageBoxes, severity: .warn, title: "No bleed", detail: "", page: 0),
        ]
        let result = PreflightService.mergeResults(rustChecks: rustChecks, swiftChecks: swiftChecks)
        #expect(result.checks.count == 2)
        #expect(result.worstSeverity == .warn)
    }
}
