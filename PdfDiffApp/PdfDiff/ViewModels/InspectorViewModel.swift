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

    // Inspection state
    var inspectionResult: InspectionResult?
    var isInspecting = false
    var inspectionError: String?
    var selectedIssueId: Int?
    var showInspectionSidebar = false
    var showPins = true

    // Preflight state
    var preflightResult: SwiftPreflightResult?
    var isPreflighting = false

    // Barcode state
    var detectedBarcodes: [DetectedBarcode] = []
    var showBarcodeOverlay = true

    private let pdfService: PDFServiceProtocol
    private let preflightService = PreflightService()
    private let barcodeService = BarcodeDetectionService()

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
        runPreflight()
        await detectBarcodes()
    }

    func runPreflight() {
        guard let doc = document else { return }
        isPreflighting = true
        let swiftChecks = preflightService.checkPageBoxes(pdfPath: doc.path)
        preflightResult = PreflightService.mergeResults(rustChecks: [], swiftChecks: swiftChecks)
        isPreflighting = false
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

    func detectBarcodes() async {
        guard let image = renderedImage else { return }
        detectedBarcodes = await barcodeService.detectBarcodes(in: image)

        // Add barcode results to preflight
        let barcodeChecks: [PreflightCheckItem]
        if detectedBarcodes.isEmpty {
            barcodeChecks = [PreflightCheckItem(
                category: .barcodes, severity: .info,
                title: "No barcodes detected", detail: "No barcodes found on this page.", page: currentPage
            )]
        } else {
            barcodeChecks = detectedBarcodes.map { barcode in
                PreflightCheckItem(
                    category: .barcodes, severity: .pass,
                    title: "\(barcode.displaySymbology) detected",
                    detail: barcode.payload,
                    page: currentPage
                )
            }
        }

        // Merge with existing preflight result
        if let existing = preflightResult {
            let nonBarcodeChecks = existing.checks.filter { $0.category != .barcodes }
            preflightResult = SwiftPreflightResult(checks: nonBarcodeChecks + barcodeChecks)
        } else {
            preflightResult = SwiftPreflightResult(checks: barcodeChecks)
        }
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
