import SwiftUI

@Observable @MainActor
final class CompareViewModel {
    enum CompareMode: String, CaseIterable {
        case overlay = "Overlay"
        case sideBySide = "Side by Side"
        case swipe = "Swipe"
        case onionSkin = "Onion Skin"
    }

    enum OverlaySubMode: String, CaseIterable {
        case blink = "Blink"
        case diff = "Diff"
    }

    var overlaySubMode: OverlaySubMode = .blink
    var diffOverlayColor: Color = .red
    var diffOverlayOpacity: Double = 0.5

    var leftDocument: OpenedDocument?
    var rightDocument: OpenedDocument?
    var currentPage: UInt32 = 0
    var compareMode: CompareMode = .overlay
    var sensitivity: Float = 0.1
    var isComparing = false
    var errorMessage: String?

    var leftImage: NSImage?
    var rightImage: NSImage?
    var diffResult: PDFDiffResult?
    var structuralDiff: PDFStructuralDiffResult?

    // AI Analysis
    var aiResult: AIAnalysisResult?
    var isAnalyzing = false
    var aiError: String?
    private var aiCache: [String: AIAnalysisResult] = [:]

    // Zoom state (shared across modes, persists on mode switch)
    var zoomLevel: CGFloat = 1.0
    var panOffset: CGSize = .zero

    // Drawer state
    enum DrawerPanel: String, CaseIterable {
        case diffSummary, aiAnalysis
    }
    var activeDrawer: DrawerPanel? = nil

    func toggleDrawer(_ panel: DrawerPanel) {
        withAnimation(DesignTokens.Motion.snappy) {
            activeDrawer = activeDrawer == panel ? nil : panel
        }
    }

    func dismissDrawer() {
        withAnimation(DesignTokens.Motion.snappy) {
            activeDrawer = nil
        }
    }

    let pdfService: PDFServiceProtocol

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

    var canRunAIAnalysis: Bool {
        hasDocuments && diffResult != nil && !isAnalyzing
    }

    func setDocuments(left: OpenedDocument, right: OpenedDocument) async {
        clearStaleState()
        self.leftDocument = left
        self.rightDocument = right
        self.currentPage = 0
        await renderAndDiff()
    }

    func setLeftDocument(_ doc: OpenedDocument) {
        clearStaleState()
        leftDocument = doc
        if hasDocuments {
            currentPage = 0
            Task { await renderAndDiff() }
        }
    }

    func setRightDocument(_ doc: OpenedDocument) {
        clearStaleState()
        rightDocument = doc
        if hasDocuments {
            currentPage = 0
            Task { await renderAndDiff() }
        }
    }

    private func clearStaleState() {
        leftImage = nil
        rightImage = nil
        diffResult = nil
        structuralDiff = nil
        aiResult = nil
        aiError = nil
        aiCache.removeAll()
    }

    func clearLeftDocument() {
        leftDocument = nil
        leftImage = nil
        diffResult = nil
        structuralDiff = nil
    }

    func clearRightDocument() {
        rightDocument = nil
        rightImage = nil
        diffResult = nil
        structuralDiff = nil
    }

    func swapDocuments() {
        let temp = leftDocument
        leftDocument = rightDocument
        rightDocument = temp
        let tempImg = leftImage
        leftImage = rightImage
        rightImage = tempImg
        if hasDocuments {
            Task { await renderAndDiff() }
        }
    }

    func nextPage() {
        guard maxPageCount > 0, currentPage < maxPageCount - 1 else { return }
        currentPage += 1
        zoomLevel = 1.0
        panOffset = .zero
        Task { await renderAndDiff() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        zoomLevel = 1.0
        panOffset = .zero
        Task { await renderAndDiff() }
    }

    func updateSensitivity(_ newValue: Float) {
        sensitivity = newValue
        Task { await computeDiff() }
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

    func runAIAnalysis(apiKey: String? = nil, service: AIAnalysisServiceProtocol? = nil) async {
        guard let left = leftImage, let right = rightImage,
              let diffRes = diffResult,
              let structDiff = structuralDiff else { return }

        // Check cache
        let cacheKey = "\(leftDocument?.path ?? ""):\(rightDocument?.path ?? ""):page\(currentPage)"
        if let cached = aiCache[cacheKey] {
            aiResult = cached
            return
        }

        let analysisService: AIAnalysisServiceProtocol
        if let service = service {
            analysisService = service
        } else if let key = apiKey, !key.isEmpty {
            analysisService = OpenRouterAIService(apiKey: key)
        } else {
            aiError = "No API key configured"
            return
        }

        let diffImage = diffRes.diffImage ?? left

        isAnalyzing = true
        aiError = nil

        do {
            let result = try await analysisService.analyze(
                left: left, right: right, diff: diffImage,
                leftText: "", rightText: "",
                diffResult: diffRes, structuralDiff: structDiff
            )
            aiResult = result
            aiCache[cacheKey] = result
        } catch {
            aiError = error.localizedDescription
        }

        isAnalyzing = false
    }

    func renderAndDiff() async {
        guard let left = leftDocument, let right = rightDocument else { return }
        aiResult = nil
        aiError = nil
        zoomLevel = 1.0
        panOffset = .zero
        isComparing = true
        defer { isComparing = false }

        let service = pdfService
        let page = currentPage

        do {
            let (leftRendered, rightRendered) = try await Task.detached {
                let l = try service.renderPage(document: left, page: page, dpi: 150)
                let r = try service.renderPage(document: right, page: page, dpi: 150)
                return (l, r)
            }.value
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

        let service = pdfService
        let page = currentPage
        let sens = sensitivity

        do {
            let (pixelDiff, structDiff) = try await Task.detached {
                let pd = try service.computePixelDiff(
                    left: left, right: right,
                    page: page, dpi: 150,
                    sensitivity: sens
                )
                let sd = try service.computeStructuralDiff(left: left, right: right)
                return (pd, sd)
            }.value
            self.diffResult = pixelDiff
            self.structuralDiff = structDiff
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
