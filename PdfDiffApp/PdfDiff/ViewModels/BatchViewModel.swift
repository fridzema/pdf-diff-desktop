import SwiftUI

@Observable @MainActor
final class BatchViewModel {
    var pairs: [BatchPair] = []
    var isProcessing = false

    private let pdfService: PDFServiceProtocol
    private let preflightService = PreflightService()

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    func addFolder(url: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension.lowercased() == "pdf" }) else { return }

        let names = files.map { $0.lastPathComponent }
        let matched = BatchMatcher.autoMatch(fileNames: names)

        pairs = matched.map { match in
            let leftURL = files.first { $0.lastPathComponent == match.leftName }!
            let rightURL = files.first { $0.lastPathComponent == match.rightName }!
            return BatchPair(
                leftPath: leftURL.path,
                rightPath: rightURL.path,
                leftName: match.leftName,
                rightName: match.rightName
            )
        }
    }

    func processAll() async {
        isProcessing = true
        defer { isProcessing = false }

        let service = pdfService
        let snapshot = pairs

        await withTaskGroup(of: (Int, Double?, String?).self) { group in
            var active = 0
            var nextIndex = 0

            while nextIndex < snapshot.count || active > 0 {
                // Launch up to 4 concurrent tasks
                while active < 4 && nextIndex < snapshot.count {
                    let i = nextIndex
                    let pair = snapshot[i]
                    pairs[i].status = .processing
                    nextIndex += 1
                    active += 1

                    group.addTask {
                        do {
                            let left = try service.openDocument(path: pair.leftPath)
                            let right = try service.openDocument(path: pair.rightPath)
                            let diff = try service.computePixelDiff(
                                left: left, right: right, page: 0, dpi: 72, sensitivity: 0.05
                            )
                            return (i, diff.similarityScore, nil)
                        } catch {
                            return (i, nil, error.localizedDescription)
                        }
                    }
                }

                // Wait for one to complete before launching next
                if let (i, score, error) = await group.next() {
                    active -= 1
                    if let score {
                        pairs[i].similarityScore = score
                        pairs[i].status = .complete
                    } else {
                        pairs[i].status = .error
                        pairs[i].errorMessage = error
                    }
                }
            }
        }
    }

    var completedCount: Int { pairs.filter { $0.status == .complete }.count }
    var totalCount: Int { pairs.count }
}
