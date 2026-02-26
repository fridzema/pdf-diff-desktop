import SwiftUI

struct OverlayView: View {
    let diffResult: PDFDiffResult?

    var body: some View {
        if let result = diffResult, let diffImage = result.diffImage {
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Image(nsImage: diffImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    // Draw changed region outlines
                    GeometryReader { geometry in
                        let imageSize = diffImage.size
                        let scaleX = geometry.size.width / imageSize.width
                        let scaleY = geometry.size.height / imageSize.height
                        let scale = min(scaleX, scaleY)

                        ForEach(Array(result.changedRegions.enumerated()), id: \.offset) { _, region in
                            Rectangle()
                                .stroke(Color.yellow, lineWidth: 1)
                                .frame(
                                    width: region.width * scale,
                                    height: region.height * scale
                                )
                                .position(
                                    x: (region.origin.x + region.width / 2) * scale,
                                    y: (region.origin.y + region.height / 2) * scale
                                )
                        }
                    }
                }
            }

            // Summary bar
            HStack {
                Text(String(format: "%.1f%% similar", (result.similarityScore) * 100))
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(result.changedPixelCount) changed pixels of \(result.totalPixelCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No diff result available")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
