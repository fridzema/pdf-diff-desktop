import Foundation

enum PreflightCheckSeverity: String, Codable, CaseIterable, Comparable {
    case pass, info, warn, fail

    private var sortOrder: Int {
        switch self {
        case .pass: return 0
        case .info: return 1
        case .warn: return 2
        case .fail: return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum PreflightCheckCategory: String, Codable, CaseIterable {
    case inkCoverage, pageConsistency, pageBoxes, fonts, images
    case colorSpace, spotColors, transparency, overprint, barcodes

    var displayName: String {
        switch self {
        case .inkCoverage: return "Ink Coverage"
        case .pageConsistency: return "Page Consistency"
        case .pageBoxes: return "Page Boxes"
        case .fonts: return "Fonts"
        case .images: return "Images"
        case .colorSpace: return "Color Space"
        case .spotColors: return "Spot Colors"
        case .transparency: return "Transparency"
        case .overprint: return "Overprint"
        case .barcodes: return "Barcodes"
        }
    }
}

struct PreflightCheckItem: Identifiable {
    let id = UUID()
    let category: PreflightCheckCategory
    let severity: PreflightCheckSeverity
    let title: String
    let detail: String
    let page: UInt32?
}

struct PreflightSummaryResult {
    let passCount: Int
    let warnCount: Int
    let failCount: Int
    let infoCount: Int
}

struct SwiftPreflightResult {
    let checks: [PreflightCheckItem]

    var summary: PreflightSummaryResult {
        PreflightSummaryResult(
            passCount: checks.filter { $0.severity == .pass }.count,
            warnCount: checks.filter { $0.severity == .warn }.count,
            failCount: checks.filter { $0.severity == .fail }.count,
            infoCount: checks.filter { $0.severity == .info }.count
        )
    }

    var worstSeverity: PreflightCheckSeverity {
        checks.map(\.severity).max() ?? .pass
    }

    var groupedByCategory: [(category: PreflightCheckCategory, checks: [PreflightCheckItem])] {
        var groups: [PreflightCheckCategory: [PreflightCheckItem]] = [:]
        for check in checks {
            groups[check.category, default: []].append(check)
        }
        return PreflightCheckCategory.allCases.compactMap { cat in
            guard let items = groups[cat] else { return nil }
            return (category: cat, checks: items)
        }
    }
}
