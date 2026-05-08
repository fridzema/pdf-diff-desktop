import Foundation
import AppKit

final class UniFFIPDFService: PDFServiceProtocol, @unchecked Sendable {
    private var documents: [UUID: PdfDocument] = [:]
    private let lock = NSLock()

    func openDocument(path: String) throws -> OpenedDocument {
        let doc = try PdfDocument.open(path: path)
        let opened = OpenedDocument(
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            pageCount: doc.pageCount()
        )
        lock.withLock { documents[opened.id] = doc }
        return opened
    }

    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap {
        let doc = try lookupDocument(document)
        let rendered = try doc.renderPage(page: page, dpi: dpi, colorspace: .rgb)
        guard let image = makeImage(from: rendered.bitmap, width: rendered.width, height: rendered.height) else {
            throw NSError(domain: "UniFFIPDFService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bitmap conversion failed for page \(page)"])
        }
        return RenderedBitmap(image: image, width: rendered.width, height: rendered.height)
    }

    func metadata(document: OpenedDocument) throws -> PDFMetadata {
        let meta = try lookupDocument(document).metadata()
        return PDFMetadata(
            title: meta.title,
            author: meta.author,
            creator: meta.creator,
            producer: meta.producer,
            creationDate: meta.creationDate,
            modificationDate: meta.modificationDate,
            pdfVersion: meta.pdfVersion,
            pageCount: meta.pageCount,
            fileSizeBytes: meta.fileSizeBytes,
            isEncrypted: meta.isEncrypted,
            colorProfiles: meta.colorProfiles.map { "\($0.name) (\($0.colorspace))" }
        )
    }

    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata] {
        try lookupDocument(document).pagesMetadata().map {
            PDFPageMetadata(
                pageNumber: $0.pageNumber,
                widthPt: $0.widthPt,
                heightPt: $0.heightPt,
                rotation: $0.rotation,
                fontNames: $0.fontNames,
                imageCount: $0.imageCount
            )
        }
    }

    func layers(document: OpenedDocument) throws -> [PDFLayer] {
        try lookupDocument(document).layers().map { PDFLayer(name: $0.name, isVisible: $0.isVisible) }
    }

    func separations(document: OpenedDocument, page: UInt32) throws -> [PDFSeparation] {
        try lookupDocument(document).separations(page: page).map { PDFSeparation(name: $0.name, colorspace: $0.colorspace) }
    }

    func computePixelDiff(left: OpenedDocument, right: OpenedDocument, page: UInt32, dpi: UInt32, sensitivity: Float) throws -> PDFDiffResult {
        let leftDoc = try lookupDocument(left)
        let rightDoc = try lookupDocument(right)
        let result = try computePixelDiffUniffi(left: leftDoc, right: rightDoc, page: page, dpi: dpi, sensitivity: sensitivity)
        return PDFDiffResult(
            similarityScore: result.similarityScore,
            diffImage: makeImage(from: result.diffBitmap, width: result.width, height: result.height),
            changedRegions: result.changedRegions.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) },
            changedPixelCount: result.changedPixelCount,
            totalPixelCount: result.totalPixelCount
        )
    }

    func computeStructuralDiff(left: OpenedDocument, right: OpenedDocument) throws -> PDFStructuralDiffResult {
        let leftDoc = try lookupDocument(left)
        let rightDoc = try lookupDocument(right)
        let result = try computeStructuralDiffUniffi(left: leftDoc, right: rightDoc)
        return PDFStructuralDiffResult(
            metadataChanges: result.metadataChanges.map { (field: $0.field, left: $0.leftValue, right: $0.rightValue) },
            textChanges: result.textChanges.map { (page: $0.page, left: $0.leftText, right: $0.rightText) },
            fontChanges: result.fontChanges.map { (page: $0.page, left: $0.leftFonts, right: $0.rightFonts) },
            pageSizeChanges: result.pageSizeChanges.map {
                (page: $0.page,
                 leftSize: CGSize(width: $0.leftWidth, height: $0.leftHeight),
                 rightSize: CGSize(width: $0.rightWidth, height: $0.rightHeight))
            }
        )
    }

    private func lookupDocument(_ doc: OpenedDocument) throws -> PdfDocument {
        let result: PdfDocument? = lock.withLock { documents[doc.id] }
        guard let pdfDoc = result else {
            throw NSError(domain: "UniFFIPDFService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Document not open: \(doc.path)"])
        }
        return pdfDoc
    }

    private func makeImage(from data: Data, width: UInt32, height: UInt32) -> NSImage? {
        let bytesPerRow = Int(width) * 4
        guard data.count == bytesPerRow * Int(height) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: Int(width), height: Int(height),
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: Int(width), height: Int(height)))
    }
}
