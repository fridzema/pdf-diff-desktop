import Testing
import AppKit
@testable import PdfDiff

@Suite("InspectorViewModel Tests")
@MainActor
struct InspectorViewModelTests {
    let mockService = MockPDFService()

    @Test("inspection state defaults to nil/false")
    func inspectionDefaults() {
        let vm = InspectorViewModel(pdfService: mockService)
        #expect(vm.inspectionResult == nil)
        #expect(!vm.isInspecting)
        #expect(vm.inspectionError == nil)
        #expect(vm.selectedIssueId == nil)
        #expect(!vm.showInspectionSidebar)
        #expect(vm.showPins)
    }

    @Test("canRunInspection is false without document")
    func cannotInspectWithoutDoc() {
        let vm = InspectorViewModel(pdfService: mockService)
        #expect(!vm.canRunInspection)
    }

    @Test("canRunInspection is true with document and rendered image")
    func canInspectWithDoc() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)
        #expect(vm.canRunInspection)
    }

    @Test("runInspection populates result on success")
    func inspectionSuccess() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        let mockAI = MockAIAnalysisService()
        await vm.runInspection(service: mockAI)

        #expect(vm.inspectionResult != nil)
        #expect(vm.inspectionError == nil)
        #expect(vm.showInspectionSidebar)
        #expect(!vm.isInspecting)
        #expect(mockAI.inspectCallCount == 1)
    }

    @Test("runInspection sets error on failure")
    func inspectionFailure() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        let mockAI = MockAIAnalysisService()
        mockAI.mockError = AIAnalysisError.invalidAPIKey
        await vm.runInspection(service: mockAI)

        #expect(vm.inspectionResult == nil)
        #expect(vm.inspectionError != nil)
        #expect(vm.inspectionError!.contains("Invalid API key"))
        #expect(!vm.isInspecting)
    }

    @Test("runInspection without key or service sets error")
    func inspectionNoKey() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        await vm.runInspection()

        #expect(vm.inspectionError == "No API key configured")
    }

    @Test("inspection results cleared on new document")
    func resultsClearedOnNewDoc() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc1 = try! mockService.openDocument(path: "/test1.pdf")
        await vm.loadDocument(doc1)
        let mockAI = MockAIAnalysisService()
        await vm.runInspection(service: mockAI)
        #expect(vm.inspectionResult != nil)

        let doc2 = try! mockService.openDocument(path: "/test2.pdf")
        await vm.loadDocument(doc2)
        #expect(vm.inspectionResult == nil)
        #expect(!vm.showInspectionSidebar)
    }

    @Test("selectedIssueId can be set and cleared")
    func selectedIssueId() async {
        let vm = InspectorViewModel(pdfService: mockService)
        vm.selectedIssueId = 1
        #expect(vm.selectedIssueId == 1)
        vm.selectedIssueId = nil
        #expect(vm.selectedIssueId == nil)
    }
}
