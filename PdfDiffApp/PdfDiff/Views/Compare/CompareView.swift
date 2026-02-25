import SwiftUI

struct CompareView: View {
    @State var viewModel: CompareViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: mode picker, sensitivity, page navigation
            compareToolbar
            Divider()

            // Compare content area
            if viewModel.isComparing {
                ProgressView("Comparing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.hasDocuments {
                compareContent
            } else {
                Text("Select two documents to compare")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var compareToolbar: some View {
        HStack(spacing: 16) {
            // Compare mode picker
            Picker("Mode", selection: $viewModel.compareMode) {
                ForEach(CompareViewModel.CompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            // Sensitivity slider
            HStack(spacing: 8) {
                Text("Sensitivity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { viewModel.sensitivity },
                    set: { viewModel.updateSensitivity($0) }
                ), in: 0.001...0.5)
                .frame(width: 120)
                Text(String(format: "%.1f%%", viewModel.sensitivity * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
            }

            Divider().frame(height: 20)

            // Page navigation
            HStack(spacing: 8) {
                Button(action: { viewModel.previousPage() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPage == 0)

                Text("Page \(viewModel.currentPage + 1) of \(viewModel.maxPageCount)")
                    .font(.body.monospacedDigit())

                Button(action: { viewModel.nextPage() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.currentPage >= viewModel.maxPageCount - 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var compareContent: some View {
        switch viewModel.compareMode {
        case .sideBySide:
            SideBySideView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                leftLabel: viewModel.leftDocument?.fileName,
                rightLabel: viewModel.rightDocument?.fileName
            )
        case .overlay:
            OverlayView(diffResult: viewModel.diffResult)
        case .swipe:
            SwipeView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        case .onionSkin:
            OnionSkinView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        }
    }
}
