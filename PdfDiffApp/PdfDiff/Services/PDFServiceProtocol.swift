import Foundation
import AppKit

protocol PDFServiceProtocol: Sendable {
    func openDocument(path: String) throws -> OpenedDocument
    func renderPage(document: OpenedDocument, page: UInt32, dpi: UInt32) throws -> RenderedBitmap
    func metadata(document: OpenedDocument) throws -> PDFMetadata
    func pagesMetadata(document: OpenedDocument) throws -> [PDFPageMetadata]
    func layers(document: OpenedDocument) throws -> [PDFLayer]
    func separations(document: OpenedDocument, page: UInt32) throws -> [PDFSeparation]
    func computePixelDiff(left: OpenedDocument, right: OpenedDocument, page: UInt32, dpi: UInt32, sensitivity: Float) throws -> PDFDiffResult
    func computeStructuralDiff(left: OpenedDocument, right: OpenedDocument) throws -> PDFStructuralDiffResult
}

// Swift-side wrapper types that map from UniFFI types
struct OpenedDocument: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let fileName: String
    let pageCount: UInt32

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: OpenedDocument, rhs: OpenedDocument) -> Bool { lhs.id == rhs.id }
}

struct RenderedBitmap {
    let image: NSImage
    let width: UInt32
    let height: UInt32
}

struct PDFMetadata {
    let title: String?
    let author: String?
    let creator: String?
    let producer: String?
    let creationDate: String?
    let modificationDate: String?
    let pdfVersion: String
    let pageCount: UInt32
    let fileSizeBytes: UInt64
    let isEncrypted: Bool
    let colorProfiles: [String]
}

struct PDFPageMetadata {
    let pageNumber: UInt32
    let widthPt: Double
    let heightPt: Double
    let rotation: UInt32
    let fontNames: [String]
    let imageCount: UInt32
}

struct PDFLayer {
    let name: String
    let isVisible: Bool
}

struct PDFSeparation {
    let name: String
    let colorspace: String
}

struct PDFDiffResult {
    let similarityScore: Double
    let diffImage: NSImage?
    let changedRegions: [CGRect]
    let changedPixelCount: UInt64
    let totalPixelCount: UInt64
}

struct PDFStructuralDiffResult {
    let metadataChanges: [(field: String, left: String?, right: String?)]
    let textChanges: [(page: UInt32, left: String, right: String)]
    let fontChanges: [(page: UInt32, left: [String], right: [String])]
    let pageSizeChanges: [(page: UInt32, leftSize: CGSize, rightSize: CGSize)]
}
