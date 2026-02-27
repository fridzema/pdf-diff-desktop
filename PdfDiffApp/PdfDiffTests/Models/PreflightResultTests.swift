import Testing
@testable import PdfDiff

@Suite("PreflightResult Tests")
struct PreflightResultTests {

    @Test("severity ordering")
    func severityOrdering() {
        let fail = PreflightCheckSeverity.fail
        let warn = PreflightCheckSeverity.warn
        let pass = PreflightCheckSeverity.pass
        let info = PreflightCheckSeverity.info
        #expect(fail.rawValue == "fail")
        #expect(warn.rawValue == "warn")
        #expect(pass.rawValue == "pass")
        #expect(info.rawValue == "info")
    }

    @Test("summary computes from checks")
    func summaryComputation() {
        let checks: [PreflightCheckItem] = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "OK", detail: "", page: nil),
            PreflightCheckItem(category: .fonts, severity: .warn, title: "Subset", detail: "", page: 0),
            PreflightCheckItem(category: .images, severity: .fail, title: "Low res", detail: "", page: 1),
            PreflightCheckItem(category: .pageBoxes, severity: .info, title: "Info", detail: "", page: nil),
        ]
        let result = SwiftPreflightResult(checks: checks)
        #expect(result.summary.passCount == 1)
        #expect(result.summary.warnCount == 1)
        #expect(result.summary.failCount == 1)
        #expect(result.summary.infoCount == 1)
    }

    @Test("worst severity")
    func worstSeverity() {
        let checks: [PreflightCheckItem] = [
            PreflightCheckItem(category: .inkCoverage, severity: .pass, title: "OK", detail: "", page: nil),
            PreflightCheckItem(category: .fonts, severity: .warn, title: "Subset", detail: "", page: nil),
        ]
        let result = SwiftPreflightResult(checks: checks)
        #expect(result.worstSeverity == .warn)
    }
}
