import Testing
import Foundation
import AppKit
@testable import PdfDiff

@Suite("AIAnalysisService Tests")
struct AIAnalysisServiceTests {
    @Test("QCStatus raw values match expected JSON strings")
    func qcStatusRawValues() {
        #expect(QCStatus.pass.rawValue == "pass")
        #expect(QCStatus.warn.rawValue == "warn")
        #expect(QCStatus.fail.rawValue == "fail")
    }

    @Test("QCCheckItem decodes from JSON")
    func qcCheckItemDecodes() throws {
        let json = """
        {"check": "Bleed", "status": "warn", "detail": "Bleed is 2mm, expected 3mm"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(QCCheckItem.self, from: json)
        #expect(item.check == "Bleed")
        #expect(item.status == .warn)
        #expect(item.detail == "Bleed is 2mm, expected 3mm")
    }

    @Test("MockAIAnalysisService returns default result")
    @MainActor
    func mockReturnsDefault() async throws {
        let mock = MockAIAnalysisService()
        let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
        let diffResult = PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
        let structuralDiff = PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])

        let result = try await mock.analyze(
            left: dummyImage, right: dummyImage, diff: dummyImage,
            leftText: "hello", rightText: "world",
            diffResult: diffResult, structuralDiff: structuralDiff
        )
        #expect(result.visualChanges == "Mock visual changes")
        #expect(mock.analyzeCallCount == 1)
    }

    @Test("MockAIAnalysisService throws when configured")
    @MainActor
    func mockThrows() async {
        let mock = MockAIAnalysisService()
        mock.mockError = NSError(domain: "Test", code: 401)
        let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
        let diffResult = PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
        let structuralDiff = PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])

        do {
            _ = try await mock.analyze(
                left: dummyImage, right: dummyImage, diff: dummyImage,
                leftText: "", rightText: "",
                diffResult: diffResult, structuralDiff: structuralDiff
            )
            Issue.record("Expected error")
        } catch {
            #expect((error as NSError).code == 401)
        }
    }
}
