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
                    .stroke(DesignTokens.issueSeverityColor(issue.severity).opacity(0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            }

            Circle()
                .fill(DesignTokens.issueSeverityColor(issue.severity))
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
                    Image(systemName: DesignTokens.issueSeverityIcon(issue.severity))
                        .foregroundStyle(DesignTokens.issueSeverityColor(issue.severity))
                    Text(issue.title)
                        .font(DesignTokens.Typo.sectionHeader)
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
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: 260)
        }
        .onAppear {
            if isSelected { isPulsing = true }
        }
        .onChange(of: isSelected) { _, selected in
            isPulsing = selected
        }
    }

}
