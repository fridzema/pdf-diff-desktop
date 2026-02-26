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
    var selectedDocuments: Set<OpenedDocument> = []
    var activeTab: ActiveTab = .inspector
    var errorMessage: String?
    var isDropTargeted = false

    let pdfService: PDFServiceProtocol
    let compareViewModel: CompareViewModel

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
        self.compareViewModel = CompareViewModel(pdfService: pdfService)
    }

    /// The single selected document for inspector mode (first in selection set)
    var selectedDocument: OpenedDocument? {
        selectedDocuments.count == 1 ? selectedDocuments.first : nil
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
        } else if newDocs.count == 1 && selectedDocuments.isEmpty {
            selectedDocuments = [newDocs[0]]
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
        let sorted = documents.filter { selectedDocuments.contains($0) }
        guard sorted.count == 2 else { return }
        enterCompareMode(left: sorted[0], right: sorted[1])
    }

    func removeDocument(_ doc: OpenedDocument) {
        documents.removeAll { $0.id == doc.id }
        selectedDocuments.remove(doc)
        if compareViewModel.leftDocument == doc {
            compareViewModel.leftDocument = nil
        }
        if compareViewModel.rightDocument == doc {
            compareViewModel.rightDocument = nil
        }
    }
}
