import Testing
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
}
