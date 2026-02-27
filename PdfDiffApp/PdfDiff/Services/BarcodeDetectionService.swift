import Foundation
import AppKit
import Vision

final class BarcodeDetectionService: @unchecked Sendable {

    func detectBarcodes(in image: NSImage) async -> [DetectedBarcode] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let barcodes = results.compactMap { obs -> DetectedBarcode? in
                    guard let payload = obs.payloadStringValue else { return nil }
                    // Vision returns bounding box in normalized coordinates (origin bottom-left)
                    // Convert to top-left origin for SwiftUI
                    let box = obs.boundingBox
                    let flipped = CGRect(
                        x: box.minX,
                        y: 1.0 - box.maxY,
                        width: box.width,
                        height: box.height
                    )
                    return DetectedBarcode(
                        symbology: obs.symbology.rawValue,
                        payload: payload,
                        boundingBox: flipped,
                        confidence: obs.confidence
                    )
                }
                continuation.resume(returning: barcodes)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
