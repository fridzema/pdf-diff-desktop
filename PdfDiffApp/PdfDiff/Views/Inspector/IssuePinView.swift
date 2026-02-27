import SwiftUI

struct IssuePinView: View {
    let issue: InspectionIssue
    let isSelected: Bool
    var onTap: () -> Void = {}

    @State private var isPulsing = false
    @State private var showPopover = false

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .stroke(severityColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            }

            Circle()
                .fill(severityColor)
                .frame(width: isSelected ? 28 : 24, height: isSelected ? 28 : 24)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            Text("\(issue.id)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .onTapGesture {
            onTap()
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: severityIcon)
                        .foregroundStyle(severityColor)
                    Text(issue.title)
                        .font(.headline)
                }
                Text(issue.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 260)
        }
        .onAppear {
            if isSelected { isPulsing = true }
        }
        .onChange(of: isSelected) { _, selected in
            isPulsing = selected
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .fail: .red
        case .warn: .orange
        case .pass: .green
        }
    }

    private var severityIcon: String {
        switch issue.severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
}
