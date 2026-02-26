import Foundation
import AppKit

@Observable @MainActor
final class InspectorViewModel {
    var document: OpenedDocument?
    var currentPage: UInt32 = 0
    var renderedImage: NSImage?
    var metadata: PDFMetadata?
    var pagesMetadata: [PDFPageMetadata] = []
    var isRendering = false
    var errorMessage: String?

    enum Tab: String, CaseIterable { case inspector, compare, separations }
    var selectedTab: Tab = .inspector

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func loadDocument(_ doc: OpenedDocument) async {
        self.document = doc
        self.currentPage = 0

        do {
            self.metadata = try pdfService.metadata(document: doc)
            self.pagesMetadata = try pdfService.pagesMetadata(document: doc)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        await renderCurrentPage()
    }

    func nextPage() {
        guard let doc = document, currentPage < doc.pageCount - 1 else { return }
        currentPage += 1
        Task { await renderCurrentPage() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        Task { await renderCurrentPage() }
    }

    private func renderCurrentPage() async {
        guard let doc = document else { return }
        isRendering = true
        defer { isRendering = false }

        do {
            let rendered = try pdfService.renderPage(document: doc, page: currentPage, dpi: 150)
            self.renderedImage = rendered.image
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
