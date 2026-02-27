import Foundation

struct BatchPair: Identifiable {
    let id = UUID()
    let leftPath: String
    let rightPath: String
    let leftName: String
    let rightName: String
    var status: BatchPairStatus = .pending
    var similarityScore: Double?
    var preflightSummary: PreflightSummaryResult?
    var errorMessage: String?
}

enum BatchPairStatus {
    case pending, processing, complete, error
}

struct BatchMatcher {
    /// Auto-match files by name similarity.
    /// Looks for version patterns: v1/v2, old/new, _1/_2, -rev1/-rev2
    static func autoMatch(fileNames: [String]) -> [(leftName: String, rightName: String)] {
        var used = Set<Int>()
        var pairs: [(String, String)] = []

        for i in 0..<fileNames.count {
            guard !used.contains(i) else { continue }
            let nameI = fileNames[i]
            let baseI = normalizeForMatching(nameI)

            for j in (i+1)..<fileNames.count {
                guard !used.contains(j) else { continue }
                let nameJ = fileNames[j]
                let baseJ = normalizeForMatching(nameJ)

                if baseI == baseJ && nameI != nameJ {
                    // Sort so "v1"/"old" comes first
                    let sorted = [nameI, nameJ].sorted()
                    pairs.append((sorted[0], sorted[1]))
                    used.insert(i)
                    used.insert(j)
                    break
                }
            }
        }

        return pairs
    }

    private static func normalizeForMatching(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: ".pdf", with: "")
            .replacingOccurrences(of: "_v1", with: "")
            .replacingOccurrences(of: "_v2", with: "")
            .replacingOccurrences(of: "_v3", with: "")
            .replacingOccurrences(of: "_old", with: "")
            .replacingOccurrences(of: "_new", with: "")
            .replacingOccurrences(of: "-v1", with: "")
            .replacingOccurrences(of: "-v2", with: "")
            .replacingOccurrences(of: "-v3", with: "")
            .replacingOccurrences(of: "-old", with: "")
            .replacingOccurrences(of: "-new", with: "")
            .replacingOccurrences(of: "_rev1", with: "")
            .replacingOccurrences(of: "_rev2", with: "")
            .replacingOccurrences(of: "_1", with: "")
            .replacingOccurrences(of: "_2", with: "")
    }
}
