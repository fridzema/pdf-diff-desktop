import Testing
import SwiftUI
import AppKit
@testable import PdfDiff

@Suite("CompareViewModel Tests")
@MainActor
struct CompareViewModelTests {
    let mockService = MockPDFService()

    @Test("sets documents and computes diff")
    func setsDocumentsAndDiffs() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        #expect(vm.leftDocument == left)
        #expect(vm.rightDocument == right)
        #expect(vm.leftImage != nil)
        #expect(vm.rightImage != nil)
        #expect(vm.diffResult != nil)
        #expect(vm.structuralDiff != nil)
    }

    @Test("page navigation syncs both sides")
    func pageNavigationSynced() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)
        #expect(vm.currentPage == 0)

        vm.nextPage()
        #expect(vm.currentPage == 1)

        vm.nextPage()
        #expect(vm.currentPage == 2)

        vm.nextPage()
        #expect(vm.currentPage == 2)

        vm.previousPage()
        #expect(vm.currentPage == 1)
    }

    @Test("does not go below page 0")
    func doesNotGoBelowZero() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        vm.previousPage()
        #expect(vm.currentPage == 0)
    }

    @Test("default compare mode is overlay")
    func defaultModeIsOverlay() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.compareMode == .overlay)
    }

    @Test("swap documents exchanges left and right")
    func swapDocuments() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)
        vm.swapDocuments()

        #expect(vm.leftDocument == right)
        #expect(vm.rightDocument == left)
    }

    @Test("set individual slot triggers diff when both filled")
    func setIndividualSlot() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        vm.setLeftDocument(left)
        #expect(vm.leftDocument == left)
        #expect(!vm.hasDocuments)

        vm.setRightDocument(right)
        #expect(vm.hasDocuments)
    }

    @Test("clear slot removes document")
    func clearSlot() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        vm.clearLeftDocument()
        #expect(vm.leftDocument == nil)
        #expect(!vm.hasDocuments)
    }

    @Test("sensitivity update stores value")
    func sensitivityUpdate() async {
        let vm = CompareViewModel(pdfService: mockService)
        vm.updateSensitivity(0.05)
        #expect(vm.sensitivity == 0.05)
    }

    @Test("maxPageCount returns minimum of both documents")
    func maxPageCount() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.maxPageCount == 0)

        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        await vm.setDocuments(left: left, right: right)

        #expect(vm.maxPageCount == 3)
    }

    // MARK: - Zoom State Tests

    @Test("zoom resets on page change")
    func zoomResetsOnPageChange() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)
        vm.zoomLevel = 2.5
        vm.panOffset = CGSize(width: 100, height: 50)

        vm.nextPage()

        #expect(vm.zoomLevel == 1.0)
        #expect(vm.panOffset == .zero)
    }

    @Test("zoom in increases zoom level")
    func zoomInIncreasesLevel() async {
        let vm = CompareViewModel(pdfService: mockService)
        let initial = vm.zoomLevel
        vm.zoomIn()
        #expect(vm.zoomLevel > initial)
    }

    @Test("zoom out decreases zoom level")
    func zoomOutDecreasesLevel() async {
        let vm = CompareViewModel(pdfService: mockService)
        vm.zoomLevel = 2.0
        vm.zoomOut()
        #expect(vm.zoomLevel < 2.0)
    }

    @Test("zoom fit resets to 1.0")
    func zoomFitResetsLevel() async {
        let vm = CompareViewModel(pdfService: mockService)
        vm.zoomLevel = 3.0
        vm.panOffset = CGSize(width: 50, height: 50)
        vm.zoomFit()
        #expect(vm.zoomLevel == 1.0)
        #expect(vm.panOffset == .zero)
    }

    // MARK: - Overlay Sub-mode Tests

    @Test("default overlay sub-mode is blink")
    func defaultOverlaySubMode() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.overlaySubMode == .blink)
    }

    @Test("diff overlay color defaults to red")
    func defaultDiffOverlayColor() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.diffOverlayColor == .red)
    }

    @Test("diff overlay opacity defaults to 0.5")
    func defaultDiffOverlayOpacity() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.diffOverlayOpacity == 0.5)
    }

    // MARK: - AI Analysis Tests

    @Test("AI analysis defaults to nil")
    func aiAnalysisDefaultsNil() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.aiResult == nil)
        #expect(!vm.isAnalyzing)
        #expect(vm.aiError == nil)
    }

    @Test("canRunAIAnalysis is false without documents")
    func cannotRunWithoutDocs() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(!vm.canRunAIAnalysis)
    }

    @Test("canRunAIAnalysis is true with documents and diff")
    func canRunWithDocsAndDiff() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)
        await vm.setDocuments(left: left, right: right)
        #expect(vm.canRunAIAnalysis)
    }

    @Test("runAIAnalysis populates result on success")
    func aiAnalysisPopulatesResult() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)
        let mockAI = MockAIAnalysisService()
        await vm.setDocuments(left: left, right: right)

        await vm.runAIAnalysis(service: mockAI)

        #expect(vm.aiResult != nil)
        #expect(vm.aiResult?.visualChanges == "Mock visual changes")
        #expect(vm.aiError == nil)
        #expect(mockAI.analyzeCallCount == 1)
    }

    @Test("runAIAnalysis sets error on failure")
    func aiAnalysisSetsError() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)
        let mockAI = MockAIAnalysisService()
        mockAI.mockError = AIAnalysisError.invalidAPIKey
        await vm.setDocuments(left: left, right: right)

        await vm.runAIAnalysis(service: mockAI)

        #expect(vm.aiResult == nil)
        #expect(vm.aiError != nil)
        #expect(vm.aiError!.contains("Invalid API key"))
    }

    @Test("AI results cleared on new comparison")
    func aiResultsClearedOnNewComparison() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)
        let mockAI = MockAIAnalysisService()
        await vm.setDocuments(left: left, right: right)
        await vm.runAIAnalysis(service: mockAI)
        #expect(vm.aiResult != nil)

        // Trigger new comparison
        await vm.renderAndDiff()
        #expect(vm.aiResult == nil)
    }

    @Test("runAIAnalysis without key or service sets error")
    func aiAnalysisNoKeyError() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)
        await vm.setDocuments(left: left, right: right)

        await vm.runAIAnalysis()

        #expect(vm.aiError == "No API key configured")
    }
}
