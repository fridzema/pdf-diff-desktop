import Foundation
import AppKit
import PDFKit

final class MockPDFService: PDFServiceProtocol, @unchecked Sendable {
    var shouldThrow = false

    // Cache opened PDFDocuments by path for rendering
    private var pdfDocuments: [String: PDFDocument] = [:]

    func openDocument(path: String) throws -> OpenedDocument {
        if shouldThrow { throw NSError(domain: "Mock", code: 1) }

        guard let pdfDoc = PDFDocument(url: URL(fileURLWithPath: path)) else {
            throw NSError(domain: "PDFService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not open PDF at \(path)"
            ])
        }

        pdfDocuments[path] = pdfDoc

        return OpenedDocument(
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            pageCount: UInt32(pdfDoc.pageCount)
        )
    }

    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap {
        guard let pdfDoc = pdfDocuments[document.path],
              let pdfPage = pdfDoc.page(at: Int(page)) else {
            throw NSError(domain: "PDFService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Page \(page) not available"
            ])
        }

        let pageRect = pdfPage.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72.0
        let width = pageRect.width * scale
        let height = pageRect.height * scale

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.cgContext.setFillColor(NSColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: NSSize(width: width, height: height)))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            pdfPage.draw(with: .mediaBox, to: ctx.cgContext)
        }
        image.unlockFocus()

        return RenderedBitmap(image: image, width: UInt32(width), height: UInt32(height))
    }

    func metadata(document: OpenedDocument) throws -> PDFMetadata {
        let pdfDoc = pdfDocuments[document.path]
        let attrs = pdfDoc?.documentAttributes

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: document.path)[.size] as? UInt64) ?? 0

        return PDFMetadata(
            title: attrs?[PDFDocumentAttribute.titleAttribute] as? String,
            author: attrs?[PDFDocumentAttribute.authorAttribute] as? String,
            creator: attrs?[PDFDocumentAttribute.creatorAttribute] as? String,
            producer: attrs?[PDFDocumentAttribute.producerAttribute] as? String,
            creationDate: (attrs?[PDFDocumentAttribute.creationDateAttribute] as? Date)?.description,
            modificationDate: (attrs?[PDFDocumentAttribute.modificationDateAttribute] as? Date)?.description,
            pdfVersion: pdfDoc?.majorVersion != nil ? "\(pdfDoc!.majorVersion).\(pdfDoc!.minorVersion)" : "unknown",
            pageCount: UInt32(pdfDoc?.pageCount ?? 0),
            fileSizeBytes: fileSize,
            isEncrypted: pdfDoc?.isEncrypted ?? false,
            colorProfiles: []
        )
    }

    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata] {
        guard let pdfDoc = pdfDocuments[document.path] else { return [] }

        return (0..<pdfDoc.pageCount).map { i in
            let page = pdfDoc.page(at: i)
            let bounds = page?.bounds(for: .mediaBox) ?? .zero
            return PDFPageMetadata(
                pageNumber: UInt32(i),
                widthPt: bounds.width,
                heightPt: bounds.height,
                rotation: UInt32(page?.rotation ?? 0),
                fontNames: [],
                imageCount: 0
            )
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
