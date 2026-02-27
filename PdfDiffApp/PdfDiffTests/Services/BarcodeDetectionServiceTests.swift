import Testing
import AppKit
@testable import PdfDiff

@Suite("BarcodeDetectionService Tests")
struct BarcodeDetectionServiceTests {

    @Test("returns empty for blank image")
    func blankImage() async {
        let service = BarcodeDetectionService()
        let blank = NSImage(size: NSSize(width: 100, height: 100))
        let results = await service.detectBarcodes(in: blank)
        #expect(results.isEmpty)
    }

    @Test("detected barcode model properties")
    func modelProperties() {
        let barcode = DetectedBarcode(
            symbology: "VNBarcodeSymbologyEAN13",
            payload: "5901234123457",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            confidence: 0.95
        )
        #expect(barcode.displaySymbology == "EAN13")
        #expect(barcode.payload == "5901234123457")
    }
}
