import SwiftUI

struct DiffOverlayView: View {
    let leftImage: NSImage?
    let diffImage: NSImage?
    @Binding var overlayColor: Color
    @Binding var overlayOpacity: Double
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    if let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }

                    if let diffImage {
                        Image(nsImage: diffImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .colorMultiply(overlayColor)
                            .opacity(overlayOpacity)
                            .blendMode(.multiply)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Diff overlay controls
            HStack(spacing: DesignTokens.Spacing.lg) {
                ColorPicker("Highlight", selection: $overlayColor, supportsOpacity: false)
                    .frame(width: 120)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Opacity")
                        .font(DesignTokens.Typo.toolbarLabel)
                        .foregroundStyle(.secondary)
                    Slider(value: $overlayOpacity, in: 0.1...1.0)
                        .frame(width: 100)
                    Text(String(format: "%.0f%%", overlayOpacity * 100))
                        .font(DesignTokens.Typo.toolbarLabel.monospacedDigit())
                        .frame(width: 36)
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(.bar)
        }
    }
}
