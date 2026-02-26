import SwiftUI

struct CompareView: View {
    @State var viewModel: CompareViewModel
    var findDocument: ((String) -> OpenedDocument?)? = nil
    var openFileAtPath: ((String) -> OpenedDocument?)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Document slots
            documentSlots
            Divider()

            if viewModel.hasDocuments {
                // Compare toolbar (mode picker, sensitivity, page nav)
                compareToolbar
                Divider()

                // Main content: visualization + diff summary
                VSplitView {
                    compareContent
                        .frame(minHeight: 300)

                    DiffSummaryPanel(
                        diffResult: viewModel.diffResult,
                        structuralDiff: viewModel.structuralDiff
                    )
                    .frame(minHeight: 120, idealHeight: 180, maxHeight: 300)
                }
            } else if viewModel.isComparing {
                ProgressView("Comparing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Drag documents into the slots above")
                        .foregroundStyle(.secondary)
                    Text("or select two in the sidebar and click Compare")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Document Slots

    private var documentSlots: some View {
        HStack(spacing: 12) {
            DocumentSlotView(
                label: "Left",
                document: viewModel.leftDocument,
                onDrop: { path in
                    if let doc = findDocument?(path) ?? openFileAtPath?(path) {
                        viewModel.setLeftDocument(doc)
                    }
                },
                onClear: { viewModel.clearLeftDocument() }
            )

            Button {
                viewModel.swapDocuments()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasDocuments)

            DocumentSlotView(
                label: "Right",
                document: viewModel.rightDocument,
                onDrop: { path in
                    if let doc = findDocument?(path) ?? openFileAtPath?(path) {
                        viewModel.setRightDocument(doc)
                    }
                },
                onClear: { viewModel.clearRightDocument() }
            )
        }
        .padding(12)
    }

    // MARK: - Toolbar

    private var compareToolbar: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $viewModel.compareMode) {
                ForEach(CompareViewModel.CompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

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

            // Zoom controls
            HStack(spacing: 4) {
                Button(action: { viewModel.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text(String(format: "%.0f%%", viewModel.zoomLevel * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
                    .onTapGesture { viewModel.zoomFit() }

                Button(action: { viewModel.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Button("Fit") { viewModel.zoomFit() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

            Divider().frame(height: 20)

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
                .disabled(viewModel.maxPageCount == 0 || viewModel.currentPage >= viewModel.maxPageCount - 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Compare Content

    @ViewBuilder
    private var compareContent: some View {
        switch viewModel.compareMode {
        case .overlay:
            AnimatedOverlayView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        case .sideBySide:
            SideBySideView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                leftLabel: viewModel.leftDocument?.fileName,
                rightLabel: viewModel.rightDocument?.fileName
            )
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
