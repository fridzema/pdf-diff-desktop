import SwiftUI

@Observable @MainActor
final class InspectorViewModel {
    var document: OpenedDocument?
    var currentPage: UInt32 = 0
    var renderedImage: NSImage?
    var metadata: PDFMetadata?
    var pagesMetadata: [PDFPageMetadata] = []
    var isRendering = false
    var errorMessage: String?

    // Zoom state
    var zoomLevel: CGFloat = 1.0
    var panOffset: CGSize = .zero

    // Inspection state
    var inspectionResult: InspectionResult?
    var isInspecting = false
    var inspectionError: String?
    var selectedIssueId: Int?
    var showInspectionSidebar = false
    var showPins = true

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    var canRunInspection: Bool {
        document != nil && renderedImage != nil && !isInspecting
    }

    func loadDocument(_ doc: OpenedDocument) async {
        self.document = doc
        self.currentPage = 0
        self.inspectionResult = nil
        self.inspectionError = nil
        self.selectedIssueId = nil
        self.showInspectionSidebar = false

        do {
            self.metadata = try pdfService.metadata(document: doc)
            self.pagesMetadata = try pdfService.pagesMetadata(document: doc)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        await renderCurrentPage()
    }

    func runInspection(apiKey: String? = nil, service: AIAnalysisServiceProtocol? = nil) async {
        guard let image = renderedImage,
              let meta = metadata,
              !pagesMetadata.isEmpty else { return }

        let analysisService: AIAnalysisServiceProtocol
        if let service = service {
            analysisService = service
        } else if let key = apiKey, !key.isEmpty {
            analysisService = OpenRouterAIService(apiKey: key)
        } else {
            inspectionError = "No API key configured"
            return
        }

        isInspecting = true
        inspectionError = nil
        inspectionResult = nil
        selectedIssueId = nil

        do {
            inspectionResult = try await analysisService.inspect(
                image: image, metadata: meta, pageMetadata: pagesMetadata[0]
            )
            showInspectionSidebar = true
        } catch {
            inspectionError = error.localizedDescription
        }

        isInspecting = false
    }

    func nextPage() {
        guard let doc = document, currentPage < doc.pageCount - 1 else { return }
        currentPage += 1
        zoomFit()
        Task { await renderCurrentPage() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        zoomFit()
        Task { await renderCurrentPage() }
    }

    func zoomIn() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoomLevel = min(10.0, zoomLevel * 1.25)
        }
    }

    func zoomOut() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoomLevel = max(0.1, zoomLevel / 1.25)
        }
    }

    func zoomFit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = 1.0
            panOffset = .zero
        }
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
