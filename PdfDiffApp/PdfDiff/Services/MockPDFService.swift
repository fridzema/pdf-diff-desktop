import Foundation
import AppKit

final class MockPDFService: PDFServiceProtocol, @unchecked Sendable {
    var shouldThrow = false

    func openDocument(path: String) throws -> OpenedDocument {
        if shouldThrow { throw NSError(domain: "Mock", code: 1) }
        return OpenedDocument(
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            pageCount: 3
        )
    }

    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap {
        let image = NSImage(size: NSSize(width: 200, height: 280))
        return RenderedBitmap(image: image, width: 200, height: 280)
    }

    func metadata(document: OpenedDocument) throws -> PDFMetadata {
        PDFMetadata(
            title: "Mock Document", author: "Test", creator: "Tests",
            producer: "MockPDF", creationDate: "2026-01-01", modificationDate: "2026-01-02",
            pdfVersion: "1.7", pageCount: 3, fileSizeBytes: 12345,
            isEncrypted: false, colorProfiles: ["sRGB"]
        )
    }

    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata] {
        (0..<3).map { i in
            PDFPageMetadata(pageNumber: UInt32(i), widthPt: 595, heightPt: 842, rotation: 0, fontNames: ["Helvetica"], imageCount: 0)
        }
    }

    func layers(document: OpenedDocument) throws -> [PDFLayer] { [] }
    func separations(document: OpenedDocument, page: UInt32) throws -> [PDFSeparation] { [] }

    func computePixelDiff(left: OpenedDocument, right: OpenedDocument, page: UInt32, dpi: UInt32, sensitivity: Float) throws -> PDFDiffResult {
        PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
    }

    func computeStructuralDiff(left: OpenedDocument, right: OpenedDocument) throws -> PDFStructuralDiffResult {
        PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])
    }
}
