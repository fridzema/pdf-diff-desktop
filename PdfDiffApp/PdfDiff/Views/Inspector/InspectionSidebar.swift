import SwiftUI

struct InspectionSidebar: View {
    let result: InspectionResult
    @Binding var selectedIssueId: Int?
    @Binding var showPins: Bool
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            issueList
            Divider()
            footer
        }
        .frame(width: 280)
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Inspection Results")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                severityBadge(.fail, count: result.issues.filter { $0.severity == .fail }.count)
                severityBadge(.warn, count: result.issues.filter { $0.severity == .warn }.count)
                severityBadge(.pass, count: result.issues.filter { $0.severity == .pass }.count)
            }
        }
        .padding(12)
    }

    private func severityBadge(_ severity: IssueSeverity, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: severityIcon(severity))
                .font(.caption2)
                .foregroundStyle(severityColor(severity))
            Text("\(count)")
                .font(.caption.monospacedDigit())
        }
    }

    // MARK: - Issue List

    private var issueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.issues) { issue in
                        issueRow(issue)
                            .id(issue.id)
                        Divider()
                    }
                }
            }
            .onChange(of: selectedIssueId) { _, newId in
                if let id = newId {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: InspectionIssue) -> some View {
        let isSelected = selectedIssueId == issue.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: severityIcon(issue.severity))
                    .foregroundStyle(severityColor(issue.severity))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("#\(issue.id)")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                        Text(issue.title)
                            .font(.caption.bold())
                            .lineLimit(isSelected ? nil : 1)
                    }

                    Text(issue.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())

                    if isSelected {
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIssueId = isSelected ? nil : issue.id
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                copyReport()
            } label: {
                Label("Copy Report", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Toggle(isOn: $showPins) {
                Label("Pins", systemImage: "mappin")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func severityIcon(_ severity: IssueSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }

    private func copyReport() {
        var report = "## AI Inspection Report\n\n"
        report += "**Summary:** \(result.summary)\n\n"
        for issue in result.issues {
            let icon = issue.severity == .pass ? "✓" : issue.severity == .warn ? "⚠" : "✗"
            report += "\(icon) **#\(issue.id) \(issue.title)** [\(issue.severity.rawValue.uppercased())]\n"
            report += "  Category: \(issue.category.rawValue)\n"
            report += "  \(issue.detail)\n\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
