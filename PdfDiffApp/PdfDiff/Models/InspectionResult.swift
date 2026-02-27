import Foundation

struct InspectionResult {
    let issues: [InspectionIssue]
    let summary: String
}

struct InspectionIssue: Identifiable {
    let id: Int
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let detail: String
    let location: IssueLocation?
}

struct IssueLocation {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }
}

enum IssueSeverity: String, Codable {
    case pass, warn, fail
}

enum IssueCategory: String, Codable {
    case bleed, resolution, colorSpace, fontEmbedding
    case overprint, transparency, barcodeUPC
    case requiredText, nutritionPanel, allergenWarning
    case recyclingSymbols, countryOfOrigin, legalDisclaimers
}
