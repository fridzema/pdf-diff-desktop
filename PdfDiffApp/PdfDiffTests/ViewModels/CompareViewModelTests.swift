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

        // Should not exceed min page count
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

    @Test("compare mode switching")
    func compareModeSwitch() async {
        let vm = CompareViewModel(pdfService: mockService)

        vm.compareMode = .overlay
        #expect(vm.compareMode == .overlay)

        vm.compareMode = .swipe
        #expect(vm.compareMode == .swipe)

        vm.compareMode = .onionSkin
        #expect(vm.compareMode == .onionSkin)

        vm.compareMode = .sideBySide
        #expect(vm.compareMode == .sideBySide)
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

        // Both mock docs have 3 pages
        #expect(vm.maxPageCount == 3)
    }
}
