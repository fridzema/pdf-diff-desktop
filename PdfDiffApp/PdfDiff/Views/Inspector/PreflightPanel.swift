import SwiftUI

struct PreflightPanel: View {
    let result: SwiftPreflightResult
    var onNavigateToPage: ((UInt32) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.groupedByCategory, id: \.category) { group in
                        DisclosureGroup {
                            ForEach(group.checks) { check in
                                checkRow(check)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                severityIcon(worstIn: group.checks)
                                Text(group.category.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(group.checks.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text("Preflight")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                if result.summary.passCount > 0 {
                    Label("\(result.summary.passCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if result.summary.warnCount > 0 {
                    Label("\(result.summary.warnCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if result.summary.failCount > 0 {
                    Label("\(result.summary.failCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if result.summary.infoCount > 0 {
                    Label("\(result.summary.infoCount)", systemImage: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func checkRow(_ check: PreflightCheckItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            severityDot(check.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.caption)
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let page = check.page {
                Button("p.\(page + 1)") {
                    onNavigateToPage?(page)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func severityIcon(worstIn checks: [PreflightCheckItem]) -> some View {
        let worst = checks.map(\.severity).max() ?? .pass
        return severityDot(worst)
    }

    @ViewBuilder
    private func severityDot(_ severity: PreflightCheckSeverity) -> some View {
        switch severity {
        case .pass:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warn:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fail:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
        }
    }
}
