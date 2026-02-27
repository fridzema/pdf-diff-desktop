import Foundation
import AppKit
import PDFKit

final class MockPDFService: PDFServiceProtocol, @unchecked Sendable {
    var shouldThrow = false

    // Cache opened PDFDocuments by path for rendering
    private var pdfDocuments: [String: PDFDocument] = [:]
    private let renderCache = RenderCache()

    func openDocument(path: String) throws -> OpenedDocument {
        if shouldThrow { throw NSError(domain: "Mock", code: 1) }

        if let pdfDoc = PDFDocument(url: URL(fileURLWithPath: path)) {
            pdfDocuments[path] = pdfDoc
            return OpenedDocument(
                path: path,
                fileName: URL(fileURLWithPath: path).lastPathComponent,
                pageCount: UInt32(pdfDoc.pageCount)
            )
        }

        // Fallback for test paths that don't exist on disk
        return OpenedDocument(
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            pageCount: 3
        )
    }

    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap {
        let cacheKey = "\(document.path):\(page):\(dpi)"
        if let cached = renderCache.get(key: cacheKey) {
            return RenderedBitmap(image: cached, width: UInt32(cached.size.width), height: UInt32(cached.size.height))
        }

        if let pdfDoc = pdfDocuments[document.path],
           let pdfPage = pdfDoc.page(at: Int(page)) {
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

            renderCache.set(key: cacheKey, image: image)
            return RenderedBitmap(image: image, width: UInt32(width), height: UInt32(height))
        }

        // Fallback mock rendering for test paths
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return RenderedBitmap(image: image, width: 100, height: 100)
    }

    func metadata(document: OpenedDocument) throws -> PDFMetadata {
        guard let pdfDoc = pdfDocuments[document.path] else {
            // Fallback mock metadata for test paths
            return PDFMetadata(
                title: nil, author: nil, creator: nil, producer: nil,
                creationDate: nil, modificationDate: nil, pdfVersion: "1.7",
                pageCount: document.pageCount,
                fileSizeBytes: 1000, isEncrypted: false, colorProfiles: []
            )
        }

        let attrs = pdfDoc.documentAttributes
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: document.path)[.size] as? UInt64) ?? 0

        return PDFMetadata(
            title: attrs?[PDFDocumentAttribute.titleAttribute] as? String,
            author: attrs?[PDFDocumentAttribute.authorAttribute] as? String,
            creator: attrs?[PDFDocumentAttribute.creatorAttribute] as? String,
            producer: attrs?[PDFDocumentAttribute.producerAttribute] as? String,
            creationDate: (attrs?[PDFDocumentAttribute.creationDateAttribute] as? Date)?.description,
            modificationDate: (attrs?[PDFDocumentAttribute.modificationDateAttribute] as? Date)?.description,
            pdfVersion: "\(pdfDoc.majorVersion).\(pdfDoc.minorVersion)",
            pageCount: UInt32(pdfDoc.pageCount),
            fileSizeBytes: fileSize,
            isEncrypted: pdfDoc.isEncrypted,
            colorProfiles: []
        )
    }

    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata] {
        guard let pdfDoc = pdfDocuments[document.path] else {
            // Fallback mock metadata for test paths
            return (0..<Int(document.pageCount)).map { i in
                PDFPageMetadata(
                    pageNumber: UInt32(i),
                    widthPt: 612, heightPt: 792,
                    rotation: 0, fontNames: [], imageCount: 0
                )
            }
        }

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
