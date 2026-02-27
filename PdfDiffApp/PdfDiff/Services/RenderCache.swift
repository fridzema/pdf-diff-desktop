import Foundation
import AppKit

final class RenderCache: @unchecked Sendable {
    private var cache: [String: (image: NSImage, size: Int)] = [:]
    private var accessOrder: [String] = []
    private let maxBytes: Int
    private var currentBytes: Int = 0
    private let lock = NSLock()

    init(maxBytes: Int = 500_000_000) { // 500MB
        self.maxBytes = maxBytes
    }

    func get(key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let entry = cache[key] {
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            return entry.image
        }
        return nil
    }

    func set(key: String, image: NSImage) {
        let size = estimateSize(image)
        lock.lock()
        defer { lock.unlock() }

        while currentBytes + size > maxBytes && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            if let entry = cache.removeValue(forKey: oldest) {
                currentBytes -= entry.size
            }
        }

        cache[key] = (image, size)
        accessOrder.append(key)
        currentBytes += size
    }

    private func estimateSize(_ image: NSImage) -> Int {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)
        return w * h * 4
    }
}
