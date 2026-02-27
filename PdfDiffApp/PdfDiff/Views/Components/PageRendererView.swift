import SwiftUI

struct PageRendererView: View {
    let image: NSImage?
    let isLoading: Bool
    let label: String?

    init(image: NSImage?, isLoading: Bool = false, label: String? = nil) {
        self.image = image
        self.isLoading = isLoading
        self.label = label
    }

    var body: some View {
        VStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(DesignTokens.Typo.toolbarLabel)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                Text("No page")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
