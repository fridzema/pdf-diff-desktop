import SwiftUI

struct CompareView: View {
    @State var viewModel: CompareViewModel
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager?
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
                        structuralDiff: viewModel.structuralDiff,
                        aiResult: viewModel.aiResult,
                        isAnalyzing: viewModel.isAnalyzing,
                        aiError: viewModel.aiError,
                        onRetry: {
                            if let key = settingsManager?.apiKey, !key.isEmpty {
                                Task { await viewModel.runAIAnalysis(apiKey: key) }
                            }
                        }
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
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            viewModel.zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            viewModel.zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
            viewModel.zoomFit()
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

            Button {
                if let key = settingsManager?.apiKey, !key.isEmpty {
                    Task { await viewModel.runAIAnalysis(apiKey: key) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("Analyze")
                }
            }
            .disabled(!viewModel.canRunAIAnalysis || settingsManager?.hasAPIKey != true)
            .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI analysis")

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
            VStack(spacing: 0) {
                // Sub-mode picker
                Picker("", selection: $viewModel.overlaySubMode) {
                    ForEach(CompareViewModel.OverlaySubMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .padding(.vertical, 6)

                switch viewModel.overlaySubMode {
                case .blink:
                    AnimatedOverlayView(
                        leftImage: viewModel.leftImage,
                        rightImage: viewModel.rightImage,
                        zoomLevel: $viewModel.zoomLevel,
                        panOffset: $viewModel.panOffset
                    )
                case .diff:
                    DiffOverlayView(
                        leftImage: viewModel.leftImage,
                        diffImage: viewModel.diffResult?.diffImage,
                        overlayColor: $viewModel.diffOverlayColor,
                        overlayOpacity: $viewModel.diffOverlayOpacity,
                        zoomLevel: $viewModel.zoomLevel,
                        panOffset: $viewModel.panOffset
                    )
                }
            }
        case .sideBySide:
            SideBySideView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                leftLabel: viewModel.leftDocument?.fileName,
                rightLabel: viewModel.rightDocument?.fileName,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        case .swipe:
            SwipeView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        case .onionSkin:
            OnionSkinView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        }
    }
}
