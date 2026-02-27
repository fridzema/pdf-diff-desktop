import SwiftUI

struct IssuePinView: View {
    let issue: InspectionIssue
    let isSelected: Bool
    var onTap: () -> Void = {}

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring (selected only)
            if isSelected {
                Circle()
                    .stroke(severityColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            }

            // Pin circle
            Circle()
                .fill(severityColor)
                .frame(width: isSelected ? 28 : 24, height: isSelected ? 28 : 24)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            // Number
            Text("\(issue.id)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .onTapGesture { onTap() }
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
}
