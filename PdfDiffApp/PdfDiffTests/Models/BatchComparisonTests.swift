import Testing
@testable import PdfDiff

@Suite("BatchComparison Tests")
struct BatchComparisonTests {

    @Test("auto-match by name similarity")
    func autoMatch() {
        let files = [
            "artwork_v1.pdf", "artwork_v2.pdf",
            "label_old.pdf", "label_new.pdf",
            "unmatched.pdf"
        ]
        let pairs = BatchMatcher.autoMatch(fileNames: files)
        #expect(pairs.count == 2)
        #expect(pairs[0].leftName == "artwork_v1.pdf")
        #expect(pairs[0].rightName == "artwork_v2.pdf")
    }

    @Test("batch pair status")
    func pairStatus() {
        var pair = BatchPair(leftPath: "/a.pdf", rightPath: "/b.pdf", leftName: "a.pdf", rightName: "b.pdf")
        #expect(pair.status == .pending)
        pair.status = .complete
        pair.similarityScore = 0.95
        #expect(pair.similarityScore == 0.95)
    }
}
