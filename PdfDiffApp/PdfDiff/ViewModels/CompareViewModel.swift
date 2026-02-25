import Foundation
import AppKit

@Observable @MainActor
final class CompareViewModel {
    enum CompareMode: String, CaseIterable {
        case sideBySide = "Side by Side"
        case overlay = "Overlay"
        case swipe = "Swipe"
        case onionSkin = "Onion Skin"
    }

    var leftDocument: OpenedDocument?
    var rightDocument: OpenedDocument?
    var currentPage: UInt32 = 0
    var compareMode: CompareMode = .sideBySide
    var sensitivity: Float = 0.1
    var isComparing = false
    var errorMessage: String?

    var leftImage: NSImage?
    var rightImage: NSImage?
    var diffResult: PDFDiffResult?
    var structuralDiff: PDFStructuralDiffResult?

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    var maxPageCount: UInt32 {
        guard let left = leftDocument, let right = rightDocument else { return 0 }
        return min(left.pageCount, right.pageCount)
    }

    var hasDocuments: Bool {
        leftDocument != nil && rightDocument != nil
    }

    func setDocuments(left: OpenedDocument, right: OpenedDocument) async {
        self.leftDocument = left
        self.rightDocument = right
        self.currentPage = 0
        await renderAndDiff()
    }

    func nextPage() {
        guard currentPage < maxPageCount - 1 else { return }
        currentPage += 1
        Task { await renderAndDiff() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        Task { await renderAndDiff() }
    }

    func updateSensitivity(_ newValue: Float) {
        sensitivity = newValue
        Task { await computeDiff() }
    }

    func renderAndDiff() async {
        guard let left = leftDocument, let right = rightDocument else { return }
        isComparing = true
        defer { isComparing = false }

        do {
            let leftRendered = try pdfService.renderPage(document: left, page: currentPage, dpi: 150)
            let rightRendered = try pdfService.renderPage(document: right, page: currentPage, dpi: 150)
            self.leftImage = leftRendered.image
            self.rightImage = rightRendered.image
        } catch {
            self.errorMessage = error.localizedDescription
            return
        }

        await computeDiff()
    }

    private func computeDiff() async {
        guard let left = leftDocument, let right = rightDocument else { return }

        do {
            self.diffResult = try pdfService.computePixelDiff(
                left: left, right: right,
                page: currentPage, dpi: 150,
                sensitivity: sensitivity
            )
            self.structuralDiff = try pdfService.computeStructuralDiff(left: left, right: right)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
