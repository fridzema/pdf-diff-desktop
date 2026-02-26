import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable @MainActor
final class AppViewModel {
    var documents: [OpenedDocument] = []
    var selectedDocument: OpenedDocument?
    var errorMessage: String?
    var isDropTargeted = false

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func openFiles(urls: [URL]) {
        let pdfUrls = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .prefix(10)

        for url in pdfUrls {
            do {
                let doc = try pdfService.openDocument(path: url.path)
                documents.append(doc)
            } catch {
                errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if documents.count == 1 {
            selectedDocument = documents.first
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let semaphore = DispatchSemaphore(value: 0)

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) { item, _ in
                    if let url = item as? URL {
                        urls.append(url)
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
        }

        guard !urls.isEmpty else { return false }
        openFiles(urls: urls)
        return true
    }

    func removeDocument(_ doc: OpenedDocument) {
        documents.removeAll { $0.id == doc.id }
        if selectedDocument == doc {
            selectedDocument = documents.first
        }
    }
}
