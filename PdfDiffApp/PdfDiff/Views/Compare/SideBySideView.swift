import SwiftUI

struct SideBySideView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let leftLabel: String?
    let rightLabel: String?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
            HStack(spacing: 1) {
                imagePanel(image: leftImage, label: leftLabel)
                Divider()
                imagePanel(image: rightImage, label: rightLabel)
            }
        }
    }

    private func imagePanel(image: NSImage?, label: String?) -> some View {
        VStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("No page")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
