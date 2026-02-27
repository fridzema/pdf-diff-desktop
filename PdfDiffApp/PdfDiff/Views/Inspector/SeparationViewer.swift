import SwiftUI

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let image: NSImage
    let coverage: Double
    var isEnabled: Bool = true
}

struct SeparationViewer: View {
    @Binding var channels: [ChannelInfo]

    var body: some View {
        HStack(spacing: 0) {
            // Composite preview
            ZoomableContainer {
                ZStack {
                    Color.white
                    ForEach(channels.filter(\.isEnabled)) { channel in
                        Image(nsImage: channel.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blendMode(.multiply)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Channel list
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Separations")
                    .font(DesignTokens.Typo.sectionHeader)
                    .padding(.bottom, 4)

                ForEach($channels) { $channel in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Toggle("", isOn: $channel.isEnabled)
                            .toggleStyle(.checkbox)
                        Circle()
                            .fill(channel.color)
                            .frame(width: 12, height: 12)
                        Text(channel.name)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f%%", channel.coverage))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                let totalCoverage = channels.filter(\.isEnabled).reduce(0.0) { $0 + $1.coverage }
                HStack {
                    Text("Total ink")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f%%", totalCoverage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(totalCoverage > 300 ? DesignTokens.Status.fail : .secondary)
                }

                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .frame(width: 200)
        }
    }
}
