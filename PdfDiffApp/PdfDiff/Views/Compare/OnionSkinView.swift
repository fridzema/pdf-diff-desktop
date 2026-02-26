import SwiftUI

struct OnionSkinView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var opacity: Double = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // Onion skin canvas
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    if let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }

                    if let rightImage {
                        Image(nsImage: rightImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Opacity control bar
            HStack(spacing: 12) {
                Text("Left")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $opacity, in: 0...1)

                Text("Right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: "%.0f%%", opacity * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 36)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
