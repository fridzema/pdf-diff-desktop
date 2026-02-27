import SwiftUI

enum DesignTokens {
    // MARK: - Spacing (8pt grid)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: - Semantic Status Colors
    enum Status {
        static let pass = Color.green
        static let warn = Color.orange
        static let fail = Color.red
        static let info = Color.blue
    }

    // MARK: - Typography
    enum Typo {
        static let toolbarLabel = Font.caption
        static let sectionHeader = Font.headline
        static let bodyMono = Font.body.monospacedDigit()
        static let metric = Font.system(.title3, design: .rounded).monospacedDigit()
    }

    // MARK: - Animation
    enum Motion {
        static let snappy = Animation.snappy(duration: 0.25)
        static let smooth = Animation.smooth(duration: 0.35)
        static let bouncy = Animation.bouncy(duration: 0.4)
    }

    // MARK: - Canvas Background
    enum Canvas {
        static let darkBackground = Color(white: 0.08)
        static let lightBackground = Color(white: 0.96)
    }

    // MARK: - Drawer
    enum Drawer {
        static let maxHeightRatio: CGFloat = 0.4
        static let cornerRadius: CGFloat = 14
        static let horizontalPadding: CGFloat = 16
    }

    // MARK: - Severity Helpers

    static func severityColor(_ severity: PreflightCheckSeverity) -> Color {
        switch severity {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        case .info: Status.info
        }
    }

    static func severityIcon(_ severity: PreflightCheckSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    static func issueSeverityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        }
    }

    static func issueSeverityIcon(_ severity: IssueSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    static func similarityColor(_ score: Double) -> Color {
        if score >= 0.99 { return Status.pass }
        if score >= 0.90 { return Status.warn }
        return Status.fail
    }

    static func qcStatusColor(_ status: QCStatus) -> Color {
        switch status {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        }
    }

    static func qcStatusIcon(_ status: QCStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
}
