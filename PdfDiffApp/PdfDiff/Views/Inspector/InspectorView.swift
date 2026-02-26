import SwiftUI

struct InspectorView: View {
    @State var viewModel: InspectorViewModel

    var body: some View {
        VSplitView {
            // Page renderer area
            VStack {
                HStack {
                    Button(action: { viewModel.previousPage() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentPage == 0)

                    Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")

                    Button(action: { viewModel.nextPage() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)
                }
                .padding(.top, 8)

                if viewModel.isRendering {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = viewModel.renderedImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else {
                    Text("No page rendered")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 300)

            // Metadata panel
            MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
                .frame(minHeight: 150, maxHeight: 300)
        }
    }
}
