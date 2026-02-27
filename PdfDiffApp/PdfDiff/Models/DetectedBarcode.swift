import Foundation

struct DetectedBarcode: Identifiable {
    let id = UUID()
    let symbology: String        // e.g., "EAN-13", "QR", "Code 128"
    let payload: String           // decoded data
    let boundingBox: CGRect       // normalized 0-1 coordinates
    let confidence: Float         // 0-1

    var displaySymbology: String {
        symbology
            .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}
