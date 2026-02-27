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

        for i in pairs.indices {
            pairs[i].status = .processing
            do {
                let left = try pdfService.openDocument(path: pairs[i].leftPath)
                let right = try pdfService.openDocument(path: pairs[i].rightPath)
                let diff = try pdfService.computePixelDiff(
                    left: left, right: right, page: 0, dpi: 72, sensitivity: 0.05
                )
                pairs[i].similarityScore = diff.similarityScore
                pairs[i].status = .complete
            } catch {
                pairs[i].status = .error
                pairs[i].errorMessage = error.localizedDescription
            }
        }
    }

    var completedCount: Int { pairs.filter { $0.status == .complete }.count }
    var totalCount: Int { pairs.count }
}
