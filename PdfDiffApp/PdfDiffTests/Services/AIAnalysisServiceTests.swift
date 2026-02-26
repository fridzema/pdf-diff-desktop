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

    @Test("AIAnalysisResult parses from valid OpenRouter JSON response")
    func parsesValidResponse() throws {
        let json = """
        {
            "visual_changes": "The logo was moved 5mm left",
            "text_comparison": "Disclaimer paragraph was reworded",
            "qc_checklist": [
                {"check": "Bleed", "status": "pass", "detail": "3mm bleed present"},
                {"check": "Resolution", "status": "warn", "detail": "Logo is 150dpi, recommended 300dpi"}
            ],
            "anomalies": "No issues found"
        }
        """.data(using: .utf8)!

        let parsed = try OpenRouterAIService.parseAnalysisResponse(json)
        #expect(parsed.visualChanges == "The logo was moved 5mm left")
        #expect(parsed.textComparison == "Disclaimer paragraph was reworded")
        #expect(parsed.qcChecklist.count == 2)
        #expect(parsed.qcChecklist[0].status == .pass)
        #expect(parsed.qcChecklist[1].status == .warn)
        #expect(parsed.anomalies == "No issues found")
    }

    @Test("parseAnalysisResponse handles missing fields gracefully")
    func parsesMissingFields() throws {
        let json = """
        {
            "visual_changes": "Something changed"
        }
        """.data(using: .utf8)!

        let parsed = try OpenRouterAIService.parseAnalysisResponse(json)
        #expect(parsed.visualChanges == "Something changed")
        #expect(parsed.textComparison.isEmpty)
        #expect(parsed.qcChecklist.isEmpty)
        #expect(parsed.anomalies.isEmpty)
    }

    @Test("encodeImageToBase64 produces valid base64 string")
    func encodesImage() throws {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: 100, height: 100)).fill()
        image.unlockFocus()

        let base64 = try OpenRouterAIService.encodeImageToBase64(image, maxBytes: 1_000_000)
        #expect(!base64.isEmpty)
        // Verify it's valid base64 by decoding
        #expect(Data(base64Encoded: base64) != nil)
    }
}
