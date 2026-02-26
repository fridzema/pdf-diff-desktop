import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable @MainActor
final class AppViewModel {
    enum ActiveTab: String, CaseIterable {
        case inspector = "Inspector"
        case compare = "Compare"
    }

    var documents: [OpenedDocument] = []
    var selectedDocumentIDs: Set<OpenedDocument.ID> = []
    var activeTab: ActiveTab = .inspector
    var errorMessage: String?
    var isDropTargeted = false

    let pdfService: PDFServiceProtocol
    let compareViewModel: CompareViewModel

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
        self.compareViewModel = CompareViewModel(pdfService: pdfService)
    }

    /// Documents currently selected in sidebar
    var selectedDocuments: [OpenedDocument] {
        documents.filter { selectedDocumentIDs.contains($0.id) }
    }

    /// The single selected document for inspector mode
    var selectedDocument: OpenedDocument? {
        selectedDocumentIDs.count == 1 ? selectedDocuments.first : nil
    }

    func openFiles(urls: [URL]) {
        let pdfUrls = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .prefix(10)

        var newDocs: [OpenedDocument] = []
        for url in pdfUrls {
            do {
                let doc = try pdfService.openDocument(path: url.path)
                documents.append(doc)
                newDocs.append(doc)
            } catch {
                errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        // Auto-enter compare mode if exactly 2 new PDFs opened
        if newDocs.count == 2 {
            enterCompareMode(left: newDocs[0], right: newDocs[1])
        } else if newDocs.count == 1 && selectedDocumentIDs.isEmpty {
            selectedDocumentIDs = [newDocs[0].id]
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let pdfProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }
        guard !pdfProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in pdfProviders {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier),
                   let url = item as? URL {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                openFiles(urls: urls)
            }
        }
        return true
    }

    func enterCompareMode(left: OpenedDocument, right: OpenedDocument) {
        activeTab = .compare
        Task {
            await compareViewModel.setDocuments(left: left, right: right)
        }
    }

    func enterCompareModeFromSelection() {
        let selected = selectedDocuments
        guard selected.count == 2 else { return }
        enterCompareMode(left: selected[0], right: selected[1])
    }

    func document(forPath path: String) -> OpenedDocument? {
        documents.first { $0.path == path }
    }

    func configureAIService(settingsManager: SettingsManager) {
        if settingsManager.hasAPIKey {
            compareViewModel.aiService = OpenRouterAIService(apiKey: settingsManager.apiKey)
        } else {
            compareViewModel.aiService = nil
        }
    }

    func removeDocument(_ doc: OpenedDocument) {
        documents.removeAll { $0.id == doc.id }
        selectedDocumentIDs.remove(doc.id)
        if compareViewModel.leftDocument == doc {
            compareViewModel.leftDocument = nil
        }
        if compareViewModel.rightDocument == doc {
            compareViewModel.rightDocument = nil
        }
    }
}
