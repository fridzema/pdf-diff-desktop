import SwiftUI

struct SideBySideView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let leftLabel: String?
    let rightLabel: String?

    var body: some View {
        HStack(spacing: 1) {
            PageRendererView(image: leftImage, label: leftLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            PageRendererView(image: rightImage, label: rightLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
