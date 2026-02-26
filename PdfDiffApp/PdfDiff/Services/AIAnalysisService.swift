import Foundation
import AppKit

enum QCStatus: String, Codable {
    case pass, warn, fail
}

struct QCCheckItem: Codable {
    let check: String
    let status: QCStatus
    let detail: String
}

struct AIAnalysisResult {
    let visualChanges: String
    let textComparison: String
    let qcChecklist: [QCCheckItem]
    let anomalies: String
}

protocol AIAnalysisServiceProtocol: Sendable {
    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult
}

final class MockAIAnalysisService: AIAnalysisServiceProtocol, @unchecked Sendable {
    var mockResult: AIAnalysisResult?
    var mockError: Error?
    var analyzeCallCount = 0

    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult {
        analyzeCallCount += 1
        if let error = mockError { throw error }
        return mockResult ?? AIAnalysisResult(
            visualChanges: "Mock visual changes",
            textComparison: "Mock text comparison",
            qcChecklist: [QCCheckItem(check: "Bleed", status: .pass, detail: "OK")],
            anomalies: "No issues found"
        )
    }
}
