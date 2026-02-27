import Testing
import Foundation
@testable import PdfDiff

@Suite("InspectionResult Tests")
struct InspectionResultTests {
    @Test("IssueSeverity raw values match expected JSON strings")
    func severityRawValues() {
        #expect(IssueSeverity.pass.rawValue == "pass")
        #expect(IssueSeverity.warn.rawValue == "warn")
        #expect(IssueSeverity.fail.rawValue == "fail")
    }

    @Test("IssueCategory raw values")
    func categoryRawValues() {
        #expect(IssueCategory.bleed.rawValue == "bleed")
        #expect(IssueCategory.barcodeUPC.rawValue == "barcodeUPC")
        #expect(IssueCategory.legalDisclaimers.rawValue == "legalDisclaimers")
    }

    @Test("IssueLocation stores percentage-based coordinates")
    func locationCoordinates() {
        let loc = IssueLocation(x: 0.1, y: 0.2, w: 0.5, h: 0.3)
        #expect(loc.x == 0.1)
        #expect(loc.y == 0.2)
        #expect(loc.w == 0.5)
        #expect(loc.h == 0.3)
    }

    @Test("IssueLocation centerX and centerY computed correctly")
    func locationCenter() {
        let loc = IssueLocation(x: 0.1, y: 0.2, w: 0.5, h: 0.3)
        #expect(loc.centerX == 0.35)  // 0.1 + 0.5/2
        #expect(loc.centerY == 0.35)  // 0.2 + 0.3/2
    }

    @Test("InspectionIssue has correct identity")
    func issueIdentity() {
        let issue = InspectionIssue(
            id: 1, severity: .fail, category: .bleed,
            title: "No bleed", detail: "Artwork has no bleed area",
            location: IssueLocation(x: 0, y: 0, w: 1, h: 0.05)
        )
        #expect(issue.id == 1)
        #expect(issue.severity == .fail)
        #expect(issue.category == .bleed)
        #expect(issue.location != nil)
    }

    @Test("InspectionIssue works without location")
    func issueWithoutLocation() {
        let issue = InspectionIssue(
            id: 2, severity: .warn, category: .colorSpace,
            title: "RGB color space", detail: "Document uses RGB",
            location: nil
        )
        #expect(issue.location == nil)
    }

    @Test("InspectionResult holds issues and summary")
    func resultStructure() {
        let result = InspectionResult(
            issues: [
                InspectionIssue(id: 1, severity: .pass, category: .bleed,
                    title: "OK", detail: "3mm bleed", location: nil)
            ],
            summary: "1 issue found"
        )
        #expect(result.issues.count == 1)
        #expect(result.summary == "1 issue found")
    }
}
